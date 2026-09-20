// Lightweight API for the SMVEC OD Flutter app.
//
// Free-tier friendly by design:
//  - Runs as a single Vercel (Hobby) serverless function.
//  - Only storage is Upstash Redis (free tier). Every request uses 1-3 Redis
//    commands, batched into one HTTP round trip where possible.
//  - Auth is stateless (HMAC-signed tokens), so checking a session costs zero
//    Redis commands.
//  - Lists (notifications, audit log) are trimmed so storage never grows unbounded.
//  - Student login OTPs are emailed via Resend or Brevo HTTP APIs (both have free tiers).
//    OTPs are stored hashed, expire in 10 minutes, and are rate limited.

import { NextResponse } from 'next/server';
import { Redis } from '@upstash/redis';
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

const kOtp = (email) => `smvec_m_otp_v1:${email}`;
const kOtpDaily = () => `smvec_m_otp_count_v1:${new Date().toISOString().slice(0, 10)}`;
const OTP_TTL_S = 600; // code valid for 10 minutes
const OTP_RESEND_S = 60; // minimum gap between two codes for the same email
const OTP_MAX_ATTEMPTS = 5;

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
    .update(`${clean(process.env.UPSTASH_REDIS_REST_TOKEN)}|${clean(process.env.STAFF_PASSWORD)}|${clean(process.env.HOD_PASSWORD)}`)
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

// Proves a student verified their email OTP; only valid for completing registration.
function signRegToken(email) {
  return sign({ e: email, p: 'reg', x: Date.now() + REG_TOKEN_TTL_MS });
}

function verifyToken(req) {
  const header = req.headers.get('authorization') || '';
  const data = readSigned(header.startsWith('Bearer ') ? header.slice(7) : '');
  if (!data || !data.e || !data.r) throw new HttpError(401, 'Session expired. Please log in again.');
  return { email: data.e, role: data.r };
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
    throw new HttpError(401, 'Incorrect password.');
  }
}

function hodEmail() {
  return (clean(process.env.HOD_EMAIL) || 'hodit@smvec.ac.in').toLowerCase();
}

function normEmail(email) {
  const e = clean(email).toLowerCase();
  if (!e.endsWith(DOMAIN) || e.length <= DOMAIN.length || /\s/.test(e)) {
    throw new HttpError(400, `Use your official ${DOMAIN} email address.`);
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

// Sends an email through whichever free provider is configured. Returns true when accepted.
//  - Resend: RESEND_API_KEY + RESEND_FROM (sender must be on a domain verified in Resend).
//  - Brevo:  BREVO_API_KEY + BREVO_FROM (a single verified sender email is enough, 300/day free).
function mailConfigured() {
  return Boolean(
    (clean(process.env.RESEND_API_KEY) && clean(process.env.RESEND_FROM)) ||
    (clean(process.env.BREVO_API_KEY) && clean(process.env.BREVO_FROM))
  );
}

async function sendMail(to, subject, html) {
  if (!to) return false;
  try {
    const resendKey = clean(process.env.RESEND_API_KEY);
    const resendFrom = clean(process.env.RESEND_FROM);
    if (resendKey && resendFrom) {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ from: resendFrom, to: [to], subject, html }),
      });
      if (res.ok) return true;
      console.warn('Resend rejected email:', res.status, await res.text().catch(() => ''));
    }
    const brevoKey = clean(process.env.BREVO_API_KEY);
    const brevoFrom = clean(process.env.BREVO_FROM);
    if (brevoKey && brevoFrom) {
      const res = await fetch('https://api.brevo.com/v3/smtp/email', {
        method: 'POST',
        headers: { 'api-key': brevoKey, 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          sender: { email: brevoFrom, name: 'SMVEC OD Portal' },
          to: [{ email: to }],
          subject,
          htmlContent: html,
        }),
      });
      if (res.ok) return true;
      console.warn('Brevo rejected email:', res.status, await res.text().catch(() => ''));
    }
  } catch (err) {
    console.warn('Email send failed:', err.message);
  }
  return false;
}

function otpHash(email, otp) {
  return crypto.createHmac('sha256', secret()).update(`${email}|${otp}`).digest('hex');
}

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

async function login(p) {
  const role = clean(p.role).toUpperCase();
  const email = normEmail(p.email);

  if (role === 'HOD') {
    if (email !== hodEmail()) throw new HttpError(403, 'This email is not the HOD account.');
    checkPassword(p.password, 'HOD_PASSWORD');
    return session({ email, role: 'HOD', name: clean(process.env.HOD_NAME) || 'Dr. R. RAJU (HOD/IT)' });
  }

  if (email === hodEmail()) throw new HttpError(400, 'Use the HOD tab to sign in with this email.');

  if (role === 'STAFF') {
    checkPassword(p.password, 'STAFF_PASSWORD');
    const profile = await getProfile(email);
    if (profile && profile.role !== 'STAFF') throw new HttpError(403, 'This email is registered as a student.');
    if (!profile) return { success: true, needsRegistration: true };
    return session(profile);
  }

  if (role === 'STUDENT') {
    return sendStudentOtp(email);
  }

  throw new HttpError(400, 'Unknown role.');
}

async function sendStudentOtp(email) {
  if (!mailConfigured()) throw new HttpError(503, 'Email service is not configured. Please contact the department.');

  const lookup = redis().pipeline();
  lookup.hget(K_USERS, email);
  lookup.get(kOtp(email));
  const [rawProfile, rawOtp] = await lookup.exec();
  const profile = parse(rawProfile);
  if (profile && profile.role !== 'STUDENT') throw new HttpError(403, 'This email is registered as staff. Use the Staff tab.');

  const previous = parse(rawOtp);
  if (previous && Date.now() - previous.t < OTP_RESEND_S * 1000) {
    const wait = Math.ceil((OTP_RESEND_S * 1000 - (Date.now() - previous.t)) / 1000);
    throw new HttpError(429, `Please wait ${wait}s before requesting another code.`);
  }

  // Global daily cap keeps us inside the email provider's free quota.
  const dailyLimit = Number(clean(process.env.OTP_DAILY_LIMIT)) || 280;
  const counter = redis().pipeline();
  counter.incr(kOtpDaily());
  counter.expire(kOtpDaily(), 26 * 60 * 60);
  const [sentToday] = await counter.exec();
  if (Number(sentToday) > dailyLimit) throw new HttpError(429, 'Daily email limit reached. Please try again tomorrow.');

  const otp = String(crypto.randomInt(100000, 1000000));
  await redis().set(kOtp(email), JSON.stringify({ h: otpHash(email, otp), a: 0, t: Date.now() }), { ex: OTP_TTL_S });

  const sent = await sendMail(
    email,
    `SMVEC OD Portal login code: ${otp}`,
    `<div style="font-family:Arial,sans-serif;max-width:480px;margin:auto;border:1px solid #e2e8f0;border-radius:10px;overflow:hidden">
       <div style="background:#3350B0;color:#fff;padding:16px;text-align:center"><b>SMVEC OD PORTAL</b><br/><small>Department of Information Technology</small></div>
       <div style="padding:20px;color:#1e293b">
         <p>Your one-time login code is:</p>
         <p style="font-size:32px;font-weight:800;letter-spacing:8px;color:#3350B0;text-align:center;margin:16px 0">${otp}</p>
         <p style="font-size:13px;color:#64748b">It is valid for 10 minutes. Do not share this code with anyone. If you did not try to sign in, ignore this email.</p>
       </div>
     </div>`
  );
  if (!sent) {
    await redis().del(kOtp(email));
    throw new HttpError(502, 'Could not send the code to your email. Please try again.');
  }
  return { success: true, otpSent: true, resendAfter: OTP_RESEND_S, expiresIn: OTP_TTL_S };
}

async function verifyStudentOtp(p) {
  const email = normEmail(p.email);
  const otp = clean(p.otp);
  if (!/^\d{6}$/.test(otp)) throw new HttpError(400, 'Enter the 6-digit code.');

  const record = parse(await redis().get(kOtp(email)));
  if (!record) throw new HttpError(400, 'Code expired. Please request a new one.');
  if (record.a >= OTP_MAX_ATTEMPTS) {
    await redis().del(kOtp(email));
    throw new HttpError(429, 'Too many wrong attempts. Please request a new code.');
  }
  if (!safeEqual(record.h, otpHash(email, otp))) {
    record.a += 1;
    await redis().set(kOtp(email), JSON.stringify(record), { keepTtl: true });
    const left = OTP_MAX_ATTEMPTS - record.a;
    throw new HttpError(400, left > 0 ? `Incorrect code. ${left} attempt${left === 1 ? '' : 's'} left.` : 'Too many wrong attempts. Please request a new code.');
  }

  // Correct code: it is single-use.
  const done = redis().pipeline();
  done.del(kOtp(email));
  done.hget(K_USERS, email);
  const [, rawProfile] = await done.exec();
  const profile = parse(rawProfile);
  if (profile && profile.role !== 'STUDENT') throw new HttpError(403, 'This email is registered as staff. Use the Staff tab.');
  if (!profile) return { success: true, needsRegistration: true, regToken: signRegToken(email) };
  return session(profile);
}

async function register(p) {
  const role = clean(p.role).toUpperCase();
  const email = normEmail(p.email);
  if (email === hodEmail()) throw new HttpError(400, 'The HOD account cannot be registered here.');

  const existing = await getProfile(email);
  let profile;

  if (role === 'STAFF') {
    checkPassword(p.password, 'STAFF_PASSWORD');
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
    const proof = readSigned(p.regToken);
    if (!proof || proof.p !== 'reg' || proof.e !== email) {
      throw new HttpError(401, 'Email verification expired. Please sign in again to get a new code.');
    }
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

  if (approve) {
    await sendMail(
      request.studentEmail,
      `On-Duty approved: ${request.eventName}`,
      `<p>Dear ${esc(request.studentName)} (${esc(request.rollNumber)}),</p>
       <p>Your On-Duty request <b>${esc(request.id)}</b> for <b>${esc(request.eventName)}</b> on ${esc(request.eventDate)} has been approved by your Class Advisor (${esc(request.advisorName)}) and the HOD.</p>
       <p>HOD remarks: ${esc(remarks)}</p><p>- SMVEC IT Department OD Portal</p>`
    );
  }
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
      case 'LOGIN':
        return json(await login(p));
      case 'VERIFY_OTP':
        return json(await verifyStudentOtp(p));
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
