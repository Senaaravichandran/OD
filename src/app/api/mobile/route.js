// Lightweight API for the SMVEC OD web portal and Flutter app.
//
// Authentication is handled entirely by Clerk. Both clients sign the user in
// with Clerk, then POST their Clerk session token once to CLERK_LOGIN. This
// route verifies that token, reads the verified email address from Clerk, and
// issues a short app session token (HMAC signed) that every later request
// carries. That exchange keeps the per-request cost at zero external calls,
// which matters on the free tier.
//
// There is no email sending here at all. Clerk owns email verification, so the
// app never needs an SMTP/API mail provider of its own.
//
// Storage is Upstash Redis only. Every request uses 1-3 Redis commands,
// batched into one HTTP round trip where possible. Lists are trimmed so
// storage never grows unbounded.

import { NextResponse } from 'next/server';
import { Redis } from '@upstash/redis';
import { createClerkClient, verifyToken as verifyClerkToken } from '@clerk/backend';
import crypto from 'crypto';

export const dynamic = 'force-dynamic';

const DOMAIN = '@smvec.ac.in';
const K_USERS = 'smvec_m_users_v1'; // hash: email -> profile JSON
const K_REQUESTS = 'smvec_m_requests_v1'; // hash: request id -> request JSON
const K_AUDIT = 'smvec_m_audit_v1'; // list, newest first
const kNotif = (email) => `smvec_m_notif_v1:${email}`; // list per user (HOD uses role key)
const K_NOTIF_HOD = 'smvec_m_notif_v1:__HOD__';

const MAX_AUDIT = 200;
const MAX_NOTIFS = 30;
const MAX_HOD_REQUESTS = 300;
const TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const REG_TOKEN_TTL_MS = 15 * 60 * 1000;

const SECTIONS = ['A', 'B', 'C', 'D', 'E', 'F'];

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const clean = (v) => (v == null ? '' : String(v).trim().replace(/^["']|["']$/g, '').trim());

let redisClient;
function redis() {
  if (redisClient) return redisClient;
  const url = clean(process.env.UPSTASH_REDIS_REST_URL);
  const token = clean(process.env.UPSTASH_REDIS_REST_TOKEN);
  if (!url || !token) throw new HttpError(503, 'Server storage is not configured.');
  redisClient = new Redis({ url, token, automaticDeserialization: false });
  return redisClient;
}

let clerk;
function clerkApi() {
  if (clerk) return clerk;
  const secretKey = clean(process.env.CLERK_SECRET_KEY);
  if (!secretKey) throw new HttpError(503, 'Sign-in is not configured on the server.');
  clerk = createClerkClient({ secretKey });
  return clerk;
}

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function json(body, status = 200) {
  return NextResponse.json(body, { status, headers: corsHeaders });
}

function parse(v) {
  if (v == null) return null;
  if (typeof v === 'object') return v;
  try {
    return JSON.parse(v);
  } catch {
    return null;
  }
}

function secret() {
  const explicit = clean(process.env.AUTH_SECRET);
  if (explicit) return explicit;
  // Fallback so the app works without extra config; set AUTH_SECRET in production.
  return crypto
    .createHash('sha256')
    .update(`${clean(process.env.UPSTASH_REDIS_REST_TOKEN)}|${clean(process.env.STAFF_PASSWORD)}`)
    .digest('hex');
}

function sign(payload) {
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const sig = crypto.createHmac('sha256', secret()).update(body).digest('base64url');
  return `${body}.${sig}`;
}

function readSigned(token) {
  const [body, sig] = String(token || '').split('.');
  if (!body || !sig) return null;
  const expected = crypto.createHmac('sha256', secret()).update(body).digest('base64url');
  if (!safeEqual(sig, expected)) return null;
  const data = parse(Buffer.from(body, 'base64url').toString());
  if (!data || !data.x || Date.now() > data.x) return null;
  return data;
}

function signToken(user) {
  return sign({ e: user.email, r: user.role, x: Date.now() + TOKEN_TTL_MS });
}

// Proves Clerk verified this email; only valid for completing registration.
function signRegToken(email) {
  return sign({ e: email, p: 'reg', x: Date.now() + REG_TOKEN_TTL_MS });
}

function bearer(req) {
  const header = req.headers.get('authorization') || '';
  return header.startsWith('Bearer ') ? header.slice(7).trim() : '';
}

function verifyToken(req) {
  const data = readSigned(bearer(req));
  if (!data || !data.e || !data.r) throw new HttpError(401, 'Session expired. Please log in again.');
  return { email: data.e, role: data.r };
}

// Verifies the Clerk session token and returns the user's verified email.
// This is the only place the app trusts an external identity.
async function emailFromClerk(req) {
  const token = bearer(req);
  if (!token) throw new HttpError(401, 'Please sign in first.');

  let claims;
  try {
    claims = await verifyClerkToken(token, { secretKey: clean(process.env.CLERK_SECRET_KEY) });
  } catch {
    throw new HttpError(401, 'Your sign-in could not be verified. Please sign in again.');
  }
  if (!claims?.sub) throw new HttpError(401, 'Your sign-in could not be verified. Please sign in again.');

  let user;
  try {
    user = await clerkApi().users.getUser(claims.sub);
  } catch {
    throw new HttpError(502, 'Could not reach the sign-in service. Please try again.');
  }

  // Only a verified primary address is trusted - an unverified one could be
  // any address the user typed in.
  const primary = (user.emailAddresses || []).find((e) => e.id === user.primaryEmailAddressId);
  if (!primary) throw new HttpError(403, 'Your account has no email address.');
  if (primary.verification?.status !== 'verified') {
    throw new HttpError(403, 'Please verify your email address before signing in.');
  }
  return normEmail(primary.emailAddress);
}

function safeEqual(a, b) {
  const ha = crypto.createHash('sha256').update(String(a)).digest();
  const hb = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(ha, hb);
}

function checkPassword(given, envName) {
  const expected = clean(process.env[envName]);
  if (!expected) throw new HttpError(503, 'Server password is not configured.');
  if (!given || !safeEqual(String(given).trim(), expected)) {
    throw new HttpError(401, 'Incorrect staff code.');
  }
}

function hodEmail() {
  return (clean(process.env.HOD_EMAIL) || 'hodit@smvec.ac.in').toLowerCase();
}

function normEmail(email) {
  const e = clean(email).toLowerCase();
  if (!e.endsWith(DOMAIN) || e.length <= DOMAIN.length || /\s/.test(e)) {
    throw new HttpError(403, `Use your official ${DOMAIN} email address to sign in.`);
  }
  return e;
}

function requireRole(auth, ...roles) {
  if (!roles.includes(auth.role)) throw new HttpError(403, 'You are not allowed to do this.');
}

function text(v, field, max = 200) {
  const s = clean(v);
  if (!s) throw new HttpError(400, `${field} is required.`);
  return s.slice(0, max);
}

function yearOf(v) {
  const y = Number(v);
  if (!Number.isInteger(y) || y < 1 || y > 4) throw new HttpError(400, 'Year must be 1, 2, 3 or 4.');
  return y;
}

function sectionOf(v) {
  const s = clean(v).toUpperCase();
  if (!SECTIONS.includes(s)) throw new HttpError(400, 'Choose a valid section.');
  return s;
}

function batchOf(v) {
  const s = clean(v);
  const m = /^(\d{4})-(\d{4})$/.exec(s);
  if (!m || Number(m[2]) - Number(m[1]) !== 4 || Number(m[1]) < 2000) {
    throw new HttpError(400, 'Batch must be in the format 2023-2027.');
  }
  return s;
}

function publicUser(p) {
  return {
    email: p.email,
    role: p.role,
    name: p.name,
    rollNumber: p.rollNumber || null,
    year: p.year || null,
    section: p.section || null,
    batch: p.batch || null,
    department: 'Information Technology',
  };
}

function session(profile) {
  return { success: true, user: publicUser(profile), token: signToken(profile) };
}

async function getProfile(email) {
  return parse(await redis().hget(K_USERS, email));
}

async function getRequest(id) {
  const r = parse(await redis().hget(K_REQUESTS, clean(id)));
  if (!r) throw new HttpError(404, 'Request not found.');
  return r;
}

// Saves the request plus its audit entry and notifications in a single pipeline.
async function saveRequest(request, audit, notifs = []) {
  const p = redis().pipeline();
  p.hset(K_REQUESTS, { [request.id]: JSON.stringify(request) });
  p.lpush(K_AUDIT, JSON.stringify({ id: `AUD-${Date.now()}`, requestId: request.id, time: new Date().toISOString(), ...audit }));
  p.ltrim(K_AUDIT, 0, MAX_AUDIT - 1);
  for (const n of notifs) {
    const key = n.to === '__HOD__' ? K_NOTIF_HOD : kNotif(n.to);
    p.lpush(key, JSON.stringify({ id: `N-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`, time: new Date().toISOString(), title: n.title, text: n.text }));
    p.ltrim(key, 0, MAX_NOTIFS - 1);
  }
  await p.exec();
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

// The single entry point after a Clerk sign-in. Trades a Clerk session token
// for an app session token, and reports whether the profile still needs to be
// filled in.
async function clerkLogin(req) {
  const email = await emailFromClerk(req);

  if (email === hodEmail()) {
    // Clerk already proved the caller controls the HOD mailbox, so there is
    // nothing further to check.
    return session({ email, role: 'HOD', name: clean(process.env.HOD_NAME) || 'Dr. R. RAJU (HOD/IT)' });
  }

  const profile = await getProfile(email);
  if (profile) return session(profile);

  return { success: true, needsRegistration: true, email, regToken: signRegToken(email) };
}

// Completes a first-time profile. The email is not taken from the request
// body - it comes from the registration token, which only CLERK_LOGIN issues.
async function register(p) {
  const proof = readSigned(p.regToken);
  if (!proof || proof.p !== 'reg' || !proof.e) {
    throw new HttpError(401, 'Your sign-in expired. Please sign in again.');
  }
  const email = proof.e;
  if (email === hodEmail()) throw new HttpError(400, 'The HOD account does not need registration.');

  const role = clean(p.role).toUpperCase();
  const existing = await getProfile(email);
  let profile;

  if (role === 'STAFF') {
    // Clerk proves who they are; the staff code proves they are an advisor.
    checkPassword(p.staffCode ?? p.password, 'STAFF_PASSWORD');
    if (existing && existing.role !== 'STAFF') throw new HttpError(403, 'This email is registered as a student.');
    profile = {
      email,
      role: 'STAFF',
      name: text(p.name, 'Name', 80),
      year: yearOf(p.year),
      section: sectionOf(p.section),
      batch: batchOf(p.batch),
    };
  } else if (role === 'STUDENT') {
    if (existing && existing.role !== 'STUDENT') throw new HttpError(403, 'This email is registered as staff.');
    profile = {
      email,
      role: 'STUDENT',
      name: text(p.name, 'Name', 80),
      rollNumber: text(p.rollNumber, 'Register number', 30).toUpperCase(),
      year: yearOf(p.year),
      section: sectionOf(p.section),
    };
  } else {
    throw new HttpError(400, 'Unknown role.');
  }

  profile.registeredAt = existing?.registeredAt || new Date().toISOString();
  await redis().hset(K_USERS, { [email]: JSON.stringify(profile) });
  return session(profile);
}

// Staff can update their class details later (for example at the start of a new year).
async function updateClass(auth, p) {
  requireRole(auth, 'STAFF');
  const profile = await getProfile(auth.email);
  if (!profile) throw new HttpError(404, 'Profile not found.');
  profile.year = yearOf(p.year);
  profile.section = sectionOf(p.section);
  profile.batch = batchOf(p.batch);
  await redis().hset(K_USERS, { [auth.email]: JSON.stringify(profile) });
  return { success: true, user: publicUser(profile) };
}

async function listAdvisors() {
  const all = await redis().hvals(K_USERS);
  const advisors = all
    .map(parse)
    .filter((u) => u && u.role === 'STAFF')
    .map((u) => ({ email: u.email, name: u.name, year: u.year, section: u.section, batch: u.batch }))
    .sort((a, b) => a.year - b.year || a.section.localeCompare(b.section) || a.name.localeCompare(b.name));
  return { success: true, advisors };
}

async function sync(auth) {
  const notifKey = auth.role === 'HOD' ? K_NOTIF_HOD : kNotif(auth.email);
  const p = redis().pipeline();
  p.hvals(K_REQUESTS);
  p.lrange(notifKey, 0, MAX_NOTIFS - 1);
  if (auth.role === 'HOD') p.lrange(K_AUDIT, 0, MAX_AUDIT - 1);
  const [rawRequests, rawNotifs, rawAudit] = await p.exec();

  let requests = (rawRequests || []).map(parse).filter(Boolean);
  if (auth.role === 'STUDENT') requests = requests.filter((r) => r.studentEmail === auth.email);
  if (auth.role === 'STAFF') requests = requests.filter((r) => r.advisorEmail === auth.email);
  requests.sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
  if (auth.role === 'HOD') requests = requests.slice(0, MAX_HOD_REQUESTS);

  return {
    success: true,
    data: {
      requests,
      notifications: (rawNotifs || []).map(parse).filter(Boolean),
      auditLogs: (rawAudit || []).map(parse).filter(Boolean),
    },
  };
}

async function createOd(auth, p) {
  requireRole(auth, 'STUDENT');
  const lookup = redis().pipeline();
  lookup.hget(K_USERS, auth.email);
  lookup.hget(K_USERS, clean(p.advisorEmail).toLowerCase());
  const [student, advisor] = await lookup.exec();
  const s = parse(student);
  const a = parse(advisor);
  if (!s) throw new HttpError(404, 'Your profile was not found. Please log in again.');
  if (!a || a.role !== 'STAFF') throw new HttpError(400, 'Please select a registered class advisor.');

  const submissionType = p.submissionType === 'TEAM' ? 'TEAM' : 'SOLO';
  const eventDate = clean(p.eventDate);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(eventDate)) throw new HttpError(400, 'Invalid event date.');

  const now = new Date();
  const request = {
    id: `OD-${now.getFullYear()}-${now.getTime().toString(36).toUpperCase()}`,
    studentName: s.name,
    studentEmail: s.email,
    rollNumber: s.rollNumber,
    department: 'Information Technology',
    year: s.year,
    section: s.section,
    advisorEmail: a.email,
    advisorName: a.name,
    submissionType,
    teamMembers: submissionType === 'TEAM' && Array.isArray(p.teamMembers)
      ? p.teamMembers.map((m) => clean(m).slice(0, 80)).filter(Boolean).slice(0, 5)
      : [],
    eventType: text(p.eventType, 'Event type', 40),
    eventName: text(p.eventName, 'Event name', 120),
    eventDate,
    eventDay: clean(p.eventDay).slice(0, 12),
    description: text(p.description, 'Description', 1000),
    status: 'PENDING_ADVISOR',
    advisorApproved: false,
    resultStatus: 'PENDING',
    createdAt: now.toISOString(),
  };

  await saveRequest(
    request,
    { action: 'CREATED', actor: `${s.name} (${s.rollNumber})`, role: 'STUDENT', details: `Submitted OD for ${request.eventName} to ${a.name}` },
    [{ to: a.email, title: 'New OD request', text: `${s.name} (${s.rollNumber}) requested OD for ${request.eventName}.` }]
  );
  return { success: true, request };
}

async function advisorDecide(auth, p) {
  requireRole(auth, 'STAFF');
  const request = await getRequest(p.reqId);
  if (request.advisorEmail !== auth.email) throw new HttpError(403, 'This request is not assigned to you.');
  if (request.status !== 'PENDING_ADVISOR') throw new HttpError(409, 'This request was already reviewed.');

  const approve = p.approve === true;
  const remarks = clean(p.remarks).slice(0, 500) || (approve ? 'Recommended by Class Advisor.' : 'Not approved by Class Advisor.');
  Object.assign(request, {
    status: approve ? 'APPROVED_BY_ADVISOR' : 'REJECTED_ADVISOR',
    advisorApproved: approve,
    advisorRemarks: remarks,
    advisorTimestamp: new Date().toISOString(),
  });

  const notifs = [{
    to: request.studentEmail,
    title: approve ? 'Advisor approved your OD' : 'Advisor rejected your OD',
    text: approve ? `${request.eventName}: forwarded to HOD for final sanction.` : `${request.eventName}: ${remarks}`,
  }];
  if (approve) notifs.push({ to: '__HOD__', title: 'OD awaiting sanction', text: `${request.studentName} - ${request.eventName} (recommended by ${request.advisorName}).` });

  await saveRequest(
    request,
    { action: approve ? 'APPROVED_BY_ADVISOR' : 'REJECTED_BY_ADVISOR', actor: request.advisorName, role: 'ADVISOR', details: `${request.id}: ${remarks}` },
    notifs
  );
  return { success: true, request };
}

async function hodDecide(auth, p) {
  requireRole(auth, 'HOD');
  const request = await getRequest(p.reqId);
  if (request.status !== 'APPROVED_BY_ADVISOR') throw new HttpError(409, 'Only advisor-approved requests can be decided by the HOD.');

  const approve = p.approve === true;
  const remarks = clean(p.remarks).slice(0, 500) || (approve ? 'Sanctioned by HOD.' : 'Not sanctioned by HOD.');
  Object.assign(request, {
    status: approve ? 'APPROVED' : 'REJECTED_HOD',
    hodRemarks: remarks,
    hodTimestamp: new Date().toISOString(),
  });

  await saveRequest(
    request,
    { action: approve ? 'APPROVED_BY_HOD' : 'REJECTED_BY_HOD', actor: 'HOD', role: 'HOD', details: `${request.id}: ${remarks}` },
    [
      { to: request.studentEmail, title: approve ? 'OD sanctioned by HOD' : 'OD rejected by HOD', text: `${request.eventName}: ${remarks}` },
      { to: request.advisorEmail, title: approve ? 'OD sanctioned' : 'OD rejected by HOD', text: `${request.studentName} - ${request.eventName}` },
    ]
  );
  return { success: true, request };
}

async function submitResult(auth, p) {
  requireRole(auth, 'STUDENT');
  const request = await getRequest(p.reqId);
  if (request.studentEmail !== auth.email) throw new HttpError(403, 'This is not your request.');
  if (request.status !== 'APPROVED') throw new HttpError(409, 'Results can be added only after the OD is approved.');

  Object.assign(request, {
    resultStatus: p.status === 'WON' ? 'WON' : 'PARTICIPATION',
    resultProjectName: clean(p.projectName).slice(0, 120) || request.eventName,
    resultDescription: clean(p.description).slice(0, 1000),
  });
  await saveRequest(request, {
    action: 'RESULT_SUBMITTED',
    actor: `${request.studentName} (${request.rollNumber})`,
    role: 'STUDENT',
    details: `${request.id}: ${request.resultStatus}`,
  });
  return { success: true, request };
}

// ---------------------------------------------------------------------------
// Route handlers
// ---------------------------------------------------------------------------

export async function OPTIONS() {
  return json({});
}

export async function POST(req) {
  try {
    const body = await req.json().catch(() => ({}));
    const action = clean(body.action);
    const p = body.payload || {};

    switch (action) {
      // Carries a Clerk session token, not an app token.
      case 'CLERK_LOGIN':
        return json(await clerkLogin(req));
      case 'REGISTER':
        return json(await register(p));
      case 'ADVISORS':
        verifyToken(req);
        return json(await listAdvisors());
      case 'SYNC':
        return json(await sync(verifyToken(req)));
      case 'UPDATE_CLASS':
        return json(await updateClass(verifyToken(req), p));
      case 'CREATE_OD':
        return json(await createOd(verifyToken(req), p));
      case 'ADVISOR_DECIDE':
        return json(await advisorDecide(verifyToken(req), p));
      case 'HOD_DECIDE':
        return json(await hodDecide(verifyToken(req), p));
      case 'SUBMIT_RESULT':
        return json(await submitResult(verifyToken(req), p));
      default:
        return json({ success: false, error: 'Unknown action.' }, 400);
    }
  } catch (err) {
    const status = err instanceof HttpError ? err.status : 500;
    if (status === 500) console.error('mobile api error:', err);
    return json({ success: false, error: status === 500 ? 'Server error. Please try again.' : err.message }, status);
  }
}
