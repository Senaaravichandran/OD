// Shared pieces for the OD API: errors, identity, and authorisation.
//
// Authorisation lives here and nowhere else. The Flutter app and the web
// portal are treated as untrusted: they decide what to *show*, never what a
// caller is allowed to *do*.

import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { one, query } from './db';
import { verifyIdToken } from './firebase-admin';

export const DOMAIN = '@smvec.ac.in';

// Staff who sign in with a password have no Firebase account, so they get an
// HMAC-signed token instead. Students never use this path.
//
// Thirty days, and it slides: every call that carries a token close to the end
// of its life gets a fresh one back, so somebody who opens the app each week
// is never asked to sign in again, while a device left untouched for a month
// stops working on its own. Twelve hours was the first guess and it meant the
// HOD typed a password every single day.
const STAFF_TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000;

/// Re-issue once the token is more than a third of the way through its life.
/// Sooner would mint a new token on nearly every call for nothing.
const STAFF_TOKEN_RENEW_AFTER_MS = 10 * 24 * 60 * 60 * 1000;

function signingSecret() {
  const explicit = clean(process.env.AUTH_SECRET);
  if (!explicit) throw new HttpError(503, 'Server signing key is not configured.');
  return explicit;
}

function timingSafeEqual(a, b) {
  const ha = crypto.createHash('sha256').update(String(a)).digest();
  const hb = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(ha, hb);
}

export function signStaffToken({ staffId, email, role }) {
  const body = Buffer.from(
    JSON.stringify({ s: staffId, e: email, r: role, x: Date.now() + STAFF_TOKEN_TTL_MS })
  ).toString('base64url');
  const sig = crypto.createHmac('sha256', signingSecret()).update(body).digest('base64url');
  return `staff.${body}.${sig}`;
}

/// A token worth replacing: valid, but old enough that the holder should be
/// given a fresh one before this one runs out.
export function staffTokenNeedsRenewal(token) {
  const data = readStaffToken(token);
  if (!data?.x) return false;
  const issuedAt = data.x - STAFF_TOKEN_TTL_MS;
  return Date.now() - issuedAt > STAFF_TOKEN_RENEW_AFTER_MS;
}

function readStaffToken(token) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3 || parts[0] !== 'staff') return null;
  const [, body, sig] = parts;
  const expected = crypto.createHmac('sha256', signingSecret()).update(body).digest('base64url');
  if (!timingSafeEqual(sig, expected)) return null;
  try {
    const data = JSON.parse(Buffer.from(body, 'base64url').toString());
    if (!data?.x || Date.now() > data.x) return null;
    return data;
  } catch {
    return null;
  }
}

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export const clean = (v) =>
  v == null ? '' : String(v).trim().replace(/^["']|["']$/g, '').replace(/﻿/g, '').trim();

export function bearer(req) {
  const header = req.headers.get('authorization') || '';
  return header.startsWith('Bearer ') ? header.slice(7).trim() : '';
}

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

/// Students must be on the college domain. Two advisors on the official roster
/// are listed with personal addresses, so a roster match is also accepted -
/// being on that roster is the department vouching for them.
export async function assertAllowedEmail(email) {
  const e = clean(email).toLowerCase();
  if (!e.includes('@')) throw new HttpError(403, `Use your official ${DOMAIN} email address.`);
  if (e.endsWith(DOMAIN) && e.length > DOMAIN.length) return e;
  const rostered = await one('select 1 from staff where email = $1', [e]);
  if (rostered) return e;
  throw new HttpError(403, `Only ${DOMAIN} accounts can use this app.`);
}

/// Resolves the caller from a Firebase ID token, creating the user row on
/// first sight. Returns the app-level identity used by every action.
export async function identify(req) {
  const token = bearer(req);
  if (!token) throw new HttpError(401, 'Please sign in first.');

  // Staff password session: re-read the account each time so a removal or a
  // role change takes effect immediately rather than living in the token.
  if (token.startsWith('staff.')) {
    const data = readStaffToken(token);
    if (!data) throw new HttpError(401, 'Your session expired. Please sign in again.');
    const staff = await one(
      `select s.id as staff_id, s.name, s.is_hod, u.id as user_id
         from staff s join users u on u.id = s.user_id
        where s.id = $1 and s.email = $2`,
      [data.s, data.e]
    );
    if (!staff) throw new HttpError(401, 'This account no longer exists.');
    return {
      userId: staff.user_id,
      staffId: staff.staff_id,
      email: data.e,
      role: staff.is_hod ? 'HOD' : 'ADVISOR',
      name: staff.name,
      // Set when the session is old enough to be worth replacing; SESSION
      // hands the caller a fresh token so an active user is never signed out.
      renewToken: staffTokenNeedsRenewal(token),
    };
  }

  let decoded;
  try {
    decoded = await verifyIdToken(token);
  } catch (err) {
    const code = err?.errorInfo?.code || err?.code || '';
    if (code.includes('id-token-expired')) throw new HttpError(401, 'Your session expired. Please sign in again.');
    if (code.includes('id-token-revoked')) throw new HttpError(401, 'You were signed out. Please sign in again.');
    throw new HttpError(401, 'Your sign-in could not be verified. Please sign in again.');
  }

  if (!decoded.email) throw new HttpError(403, 'Your account has no email address.');
  // Google always returns a verified address; anything else could be typed in.
  if (!decoded.emailVerified) throw new HttpError(403, 'Please verify your email address first.');

  const email = await assertAllowedEmail(decoded.email);

  // A rostered address is staff, whatever they signed in with.
  const staff = await one(
    `select s.id as staff_id, s.name, s.is_hod, u.id as user_id
       from staff s join users u on u.id = s.user_id
      where s.email = $1`,
    [email]
  );

  if (staff) {
    await query(
      `update users set firebase_uid = coalesce(firebase_uid, $1), last_login_at = now(),
                        photo_url = coalesce($2, photo_url)
        where id = $3`,
      [decoded.uid, decoded.picture, staff.user_id]
    );
    return {
      userId: staff.user_id,
      staffId: staff.staff_id,
      email,
      role: staff.is_hod ? 'HOD' : 'ADVISOR',
      name: staff.name,
    };
  }

  // Everyone else is a student. Students must come through Google.
  if (decoded.signInProvider && decoded.signInProvider !== 'google.com') {
    throw new HttpError(403, 'Students must sign in with Google.');
  }

  let user = await one('select id, role, display_name from users where email = $1', [email]);
  if (!user) {
    user = await one(
      `insert into users (firebase_uid, email, role, display_name, photo_url, last_login_at)
       values ($1, $2, 'STUDENT', $3, $4, now())
       returning id, role, display_name`,
      [decoded.uid, email, decoded.name || email.split('@')[0], decoded.picture]
    );
  } else {
    await query(
      `update users set firebase_uid = coalesce(firebase_uid, $1), last_login_at = now(),
                        photo_url = coalesce($2, photo_url)
        where id = $3`,
      [decoded.uid, decoded.picture, user.id]
    );
  }

  const student = await one(
    `select id, register_number, name, year, section, class_assignment_id, profile_completed
       from students where user_id = $1`,
    [user.id]
  );

  return {
    userId: user.id,
    email,
    role: 'STUDENT',
    name: student?.name || user.display_name,
    studentId: student?.id || null,
    profileCompleted: Boolean(student?.profile_completed),
    photoUrl: decoded.picture || null,
  };
}

/// Password sign-in for staff and the HOD, for shared devices where Google is
/// impractical. Never offered to students.
export async function passwordIdentify({ email, password }) {
  const e = clean(email).toLowerCase();
  const staff = await one(
    `select s.id as staff_id, s.name, s.is_hod, s.password_hash, u.id as user_id
       from staff s join users u on u.id = s.user_id
      where s.email = $1`,
    [e]
  );
  // Same message either way, so this cannot be used to discover which
  // addresses are staff.
  const wrong = new HttpError(401, 'Incorrect email or password.');
  if (!staff || !staff.password_hash) throw wrong;
  const ok = await bcrypt.compare(String(password || ''), staff.password_hash);
  if (!ok) throw wrong;

  await query('update users set last_login_at = now() where id = $1', [staff.user_id]);
  return {
    userId: staff.user_id,
    staffId: staff.staff_id,
    email: e,
    role: staff.is_hod ? 'HOD' : 'ADVISOR',
    name: staff.name,
  };
}

// ---------------------------------------------------------------------------
// Authorisation
// ---------------------------------------------------------------------------

export function requireRole(auth, ...roles) {
  if (!roles.includes(auth.role)) throw new HttpError(403, 'You are not allowed to do this.');
}

/// The classes an advisor holds. An advisor may hold more than one, and may
/// only ever see these.
export async function advisorClassIds(staffId) {
  const rows = await query(
    'select id from class_assignments where staff_id = $1 and is_active',
    [staffId]
  );
  return rows.map((r) => r.id);
}

/// Confirms the caller may act on this request, and returns it.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// Postgres rejects a malformed uuid with an error of its own, which would
/// surface as a 500. A caller that sent nothing deserves a 400.
export function uuidOf(v, message = 'A required id was missing.') {
  const id = clean(v);
  if (!UUID.test(id)) throw new HttpError(400, message);
  return id;
}

export async function requestForActor(auth, requestId) {
  const id = uuidOf(requestId, 'No OD request was specified.');

  const req = await one('select * from od_requests where id = $1', [id]);
  if (!req) throw new HttpError(404, 'Request not found.');

  if (auth.role === 'HOD') return req;
  if (auth.role === 'ADVISOR') {
    if (req.advisor_staff_id !== auth.staffId) {
      throw new HttpError(403, 'This request belongs to another class.');
    }
    return req;
  }
  if (req.student_id !== auth.studentId) throw new HttpError(403, 'This is not your request.');
  return req;
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

export function text(v, field, max = 200) {
  const s = clean(v);
  if (!s) throw new HttpError(400, `${field} is required.`);
  return s.slice(0, max);
}

export function yearOf(v) {
  const y = Number(v);
  if (!Number.isInteger(y) || y < 1 || y > 4) throw new HttpError(400, 'Year must be 1, 2, 3 or 4.');
  return y;
}

export function sectionOf(v) {
  const s = clean(v).toUpperCase();
  if (!/^[A-F]$/.test(s)) throw new HttpError(400, 'Choose a valid section.');
  return s;
}

export function dateOf(v, field = 'Date') {
  const s = clean(v);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) throw new HttpError(400, `${field} is not a valid date.`);
  return s;
}

/// Turns a database row into what the apps are allowed to see. Password
/// digests and internal ids never appear in a response.
export function publicUser(auth, extra = {}) {
  return {
    email: auth.email,
    role: auth.role,
    name: auth.name,
    department: 'Information Technology',
    ...extra,
  };
}
