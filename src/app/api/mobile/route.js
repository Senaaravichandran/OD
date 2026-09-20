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
import {
  advisorForClass,
  batchForYear,
  classMap,
  classesFor,
  isRosterEmail,
  rosterEntryForEmail,
} from '@/lib/advisor-roster';

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
  if (/\s/.test(e) || !e.includes('@')) {
    throw new HttpError(403, `Use your official ${DOMAIN} email address to sign in.`);
  }
  // Two advisors on the official roster are listed with personal addresses.
  // Being on that roster is the department vouching for them, so they are let
  // through; everyone else needs a college address.
  if (isRosterEmail(e)) return e;
  if (!e.endsWith(DOMAIN) || e.length <= DOMAIN.length) {
    throw new HttpError(403, `Use your official ${DOMAIN} email address to sign in.`);
  }
  return e;
}

/// Builds a staff profile straight from the roster, so an advisor the
/// department already listed never has to fill in a registration form.
function profileFromRoster(email) {
  const entry = rosterEntryForEmail(email);
  if (!entry) return null;
  const classes = classesFor(email);
  // An advisor holding more than one class is anchored to the first; the
  // others are recorded so it is visible in the profile.
  return {
    email: entry.email.toLowerCase(),
    role: 'STAFF',
    name: entry.name,
    year: entry.year,
    section: entry.section,
    batch: batchForYear(entry.year),
    alsoAdvises: classes.length > 1
      ? classes.slice(1).map((c) => ({ year: c.year, section: c.section }))
      : undefined,
    fromRoster: true,
  };
}

/// Finds or creates the staff profile for a roster advisor.
async function ensureRosterAdvisor(email) {
  const existing = await getProfile(email);
  if (existing) return existing;
  const profile = profileFromRoster(email);
  if (!profile) return null;
  profile.registeredAt = new Date().toISOString();
  await redis().hset(K_USERS, { [profile.email]: JSON.stringify(profile) });
  return profile;
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
    // Students pick their class advisor once, at registration, and every OD
    // they raise goes to that advisor.
    advisorEmail: p.advisorEmail || null,
    advisorName: p.advisorName || null,
    department: 'Information Technology',
  };
}

// Resolves a class advisor by email. An advisor who is on the official roster
// counts even if they have not signed in yet, so a student is never blocked
// from raising an OD by their advisor not having opened the app.
async function requireAdvisor(email) {
  const key = clean(email).toLowerCase();
  const stored = parse(await redis().hget(K_USERS, key));
  if (stored && stored.role === 'STAFF') return stored;
  if (stored && stored.role !== 'STAFF') {
    throw new HttpError(400, 'That address is not a class advisor.');
  }
  const fromRoster = profileFromRoster(key);
  if (fromRoster) return fromRoster;
  throw new HttpError(400, 'Please choose a registered class advisor.');
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

  // An advisor the department already listed goes straight in - the roster
  // already says who they are and which class they hold.
  const advisor = await ensureRosterAdvisor(email);
  if (advisor) return session(advisor);

  return { success: true, needsRegistration: true, email, regToken: signRegToken(email) };
}

// Password sign-in for staff and the HOD.
//
// Google (through Clerk) is the primary door for everyone. This second door
// exists because advisors and the HOD need to get in on shared or borrowed
// devices, and during testing, without a Google account being involved. It is
// deliberately not offered to students: their identity has to be a real,
// Clerk-verified college address, since that is what every OD is filed under.
async function passwordLogin(p) {
  const role = clean(p.role).toUpperCase();

  if (role === 'HOD') {
    checkPassword(p.password, 'HOD_PASSWORD');
    return session({
      email: hodEmail(),
      role: 'HOD',
      name: clean(process.env.HOD_NAME) || 'Dr. R. RAJU (HOD/IT)',
    });
  }

  if (role === 'STAFF') {
    checkPassword(p.password, 'STAFF_PASSWORD');
    const email = normEmail(p.email);
    if (email === hodEmail()) throw new HttpError(400, 'Use the HOD option for this address.');

    // Only the addresses on the official roster may hold a class. The staff
    // code alone is not enough - it is shared, so on its own it would let any
    // college address claim to be an advisor and start approving ODs.
    if (!isRosterEmail(email)) {
      throw new HttpError(403, 'This email is not listed as a class advisor for the department.');
    }

    const profile = await getProfile(email);
    if (profile && profile.role !== 'STAFF') {
      throw new HttpError(403, 'This email is registered as a student.');
    }
    if (profile) return session(profile);

    const advisor = await ensureRosterAdvisor(email);
    return session(advisor);
  }

  throw new HttpError(400, 'Password sign-in is only for staff and the HOD.');
}

// Lets a student correct the class they registered under. The advisor follows
// from the class, so this is how a wrong advisor gets fixed. Requests already
// filed stay with the advisor who received them.
async function changeClass(auth, p) {
  requireRole(auth, 'STUDENT');
  const profile = await getProfile(auth.email);
  if (!profile) throw new HttpError(404, 'Profile not found.');

  const year = yearOf(p.year);
  const section = sectionOf(p.section);
  const advisor = advisorForClass(year, section);
  if (!advisor) {
    throw new HttpError(400, `No class advisor is listed for Year ${year} Section ${section}.`);
  }

  profile.year = year;
  profile.section = section;
  profile.advisorEmail = advisor.email.toLowerCase();
  profile.advisorName = advisor.name;
  await redis().hset(K_USERS, { [auth.email]: JSON.stringify(profile) });
  return { success: true, user: publicUser(profile) };
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
    // Advisors on the roster never reach this form - they are provisioned from
    // the roster at sign-in. Anyone else asking to become one is refused, so a
    // leaked staff code cannot create an advisor who can approve ODs.
    if (!isRosterEmail(email)) {
      throw new HttpError(403, 'This email is not listed as a class advisor for the department.');
    }
    checkPassword(p.staffCode ?? p.password, 'STAFF_PASSWORD');
    if (existing && existing.role !== 'STAFF') throw new HttpError(403, 'This email is registered as a student.');
    profile = profileFromRoster(email);
    profile.registeredAt = existing?.registeredAt || new Date().toISOString();
    await redis().hset(K_USERS, { [email]: JSON.stringify(profile) });
    return session(profile);
  } else if (role === 'STUDENT') {
    if (existing && existing.role !== 'STUDENT') throw new HttpError(403, 'This email is registered as staff.');
    // The advisor is not something the student picks. It follows from the
    // class they are in, which is the one fact they do know.
    const year = yearOf(p.year);
    const section = sectionOf(p.section);
    const advisor = advisorForClass(year, section);
    if (!advisor) {
      throw new HttpError(400, `No class advisor is listed for Year ${year} Section ${section}.`);
    }
    profile = {
      email,
      role: 'STUDENT',
      name: text(p.name, 'Name', 80),
      rollNumber: text(p.rollNumber, 'Register number', 30).toUpperCase(),
      year,
      section,
      advisorEmail: advisor.email.toLowerCase(),
      advisorName: advisor.name,
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

// The class structure, straight from the roster, plus any advisor who has
// registered outside it. The apps use `classes` to offer only the sections
// that actually exist in a given year and to show the advisor that follows.
async function listAdvisors() {
  const classes = classMap();
  const rostered = new Set();
  const advisors = [];

  for (const { year, sections } of classes) {
    for (const s of sections) {
      rostered.add(s.advisorEmail.toLowerCase());
      advisors.push({
        email: s.advisorEmail.toLowerCase(),
        name: s.advisorName,
        year,
        section: s.section,
        batch: batchForYear(year),
      });
    }
  }

  // Staff who registered without being on the roster still belong in the list.
  const stored = (await redis().hvals(K_USERS)).map(parse).filter(Boolean);
  for (const u of stored) {
    if (u.role === 'STAFF' && !rostered.has(String(u.email).toLowerCase())) {
      advisors.push({ email: u.email, name: u.name, year: u.year, section: u.section, batch: u.batch });
    }
  }

  advisors.sort((a, b) => a.year - b.year || String(a.section).localeCompare(String(b.section)));
  return { success: true, advisors, classes };
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
  const s = parse(await redis().hget(K_USERS, auth.email));
  if (!s) throw new HttpError(404, 'Your profile was not found. Please log in again.');
  // The advisor is whoever the student is attached to - not something the
  // client gets to choose per request.
  if (!s.advisorEmail) throw new HttpError(409, 'No class advisor is set on your profile. Please set one first.');
  const a = await requireAdvisor(s.advisorEmail);

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
      case 'PASSWORD_LOGIN':
        return json(await passwordLogin(p));
      case 'REGISTER':
        return json(await register(p));
      // Public on purpose: a student needs the advisor list before they have a
      // session (to finish registering), and staff need it to pick who they
      // are on the password screen. It exposes only the staff directory -
      // name, class and college address.
      case 'ADVISORS':
        return json(await listAdvisors());
      case 'CHANGE_CLASS':
        return json(await changeClass(verifyToken(req), p));
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
