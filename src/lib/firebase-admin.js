// Firebase server-side work, done directly against Google's APIs.
//
// The firebase-admin SDK is deliberately not used here. It pulls in jwks-rsa,
// which `require()`s jose - now ESM-only - and that combination throws
// ERR_REQUIRE_ESM inside a Vercel function, crashing the route before any of
// our code runs. Verifying an ID token and sending an FCM message are both
// small, well-specified jobs, so they are implemented on Node's own crypto and
// fetch instead. No dependency, nothing to break on the next release.

import crypto from 'crypto';

const CERT_URL =
  'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

const clean = (v) =>
  (v == null ? '' : String(v)).trim().replace(/^["']|["']$/g, '').replace(/﻿/g, '');

function serviceAccount() {
  const raw = clean(process.env.FIREBASE_SERVICE_ACCOUNT);
  if (!raw) throw new Error('FIREBASE_SERVICE_ACCOUNT is not configured.');
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error('FIREBASE_SERVICE_ACCOUNT is not valid JSON.');
  }
  if (typeof parsed.private_key === 'string') {
    // Env vars usually carry the key's newlines escaped.
    parsed.private_key = parsed.private_key.replace(/\\n/g, '\n');
  }
  return parsed;
}

function projectId() {
  return clean(process.env.FIREBASE_PROJECT_ID) || serviceAccount().project_id;
}

// ---------------------------------------------------------------------------
// ID token verification
// ---------------------------------------------------------------------------

// Google rotates these certificates roughly daily and tells us when to expire
// the cache, so honour that rather than fetching on every request.
let certCache = { certs: null, expiresAt: 0 };

async function googleCerts() {
  if (certCache.certs && Date.now() < certCache.expiresAt) return certCache.certs;

  const res = await fetch(CERT_URL);
  if (!res.ok) throw new Error(`Could not fetch Google signing keys (${res.status}).`);
  const certs = await res.json();

  const cacheControl = res.headers.get('cache-control') || '';
  const maxAge = Number(/max-age=(\d+)/.exec(cacheControl)?.[1] || 3600);
  certCache = { certs, expiresAt: Date.now() + maxAge * 1000 };
  return certs;
}

const b64urlToBuffer = (s) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');

/// Verifies a Firebase ID token and returns its claims.
///
/// Checks the signature against Google's current public keys, then every claim
/// that matters: algorithm, audience, issuer, expiry, issued-at and subject.
/// A token that fails any of these is rejected.
export async function verifyIdToken(idToken) {
  const token = String(idToken || '');
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('Malformed ID token.');

  const [headerB64, payloadB64, signatureB64] = parts;

  let header;
  let claims;
  try {
    header = JSON.parse(b64urlToBuffer(headerB64).toString('utf8'));
    claims = JSON.parse(b64urlToBuffer(payloadB64).toString('utf8'));
  } catch {
    throw new Error('Malformed ID token.');
  }

  if (header.alg !== 'RS256') throw new Error('Unexpected token algorithm.');
  if (!header.kid) throw new Error('Token has no key id.');

  const certs = await googleCerts();
  const cert = certs[header.kid];
  if (!cert) throw new Error('Token was signed with an unknown key.');

  const ok = crypto
    .createVerify('RSA-SHA256')
    .update(`${headerB64}.${payloadB64}`)
    .verify(cert, b64urlToBuffer(signatureB64));
  if (!ok) throw new Error('Token signature is not valid.');

  const project = projectId();
  const now = Math.floor(Date.now() / 1000);
  const skew = 60; // tolerate a minute of clock drift either way

  if (claims.aud !== project) throw new Error('Token was issued for another project.');
  if (claims.iss !== `https://securetoken.google.com/${project}`) {
    throw new Error('Token has an unexpected issuer.');
  }
  if (typeof claims.exp !== 'number' || claims.exp + skew < now) {
    const err = new Error('Token has expired.');
    err.code = 'auth/id-token-expired';
    throw err;
  }
  if (typeof claims.iat !== 'number' || claims.iat - skew > now) {
    throw new Error('Token was issued in the future.');
  }
  if (!claims.sub) throw new Error('Token has no subject.');

  return {
    uid: claims.sub,
    email: (claims.email || '').toLowerCase(),
    emailVerified: claims.email_verified === true,
    name: claims.name || null,
    picture: claims.picture || null,
    // Which provider actually signed them in, so students can be held to
    // Google even if another provider is enabled in Firebase later.
    signInProvider: claims.firebase?.sign_in_provider || null,
  };
}

// ---------------------------------------------------------------------------
// FCM
// ---------------------------------------------------------------------------

let accessTokenCache = { token: null, expiresAt: 0 };

/// Exchanges the service account for an OAuth access token, cached until just
/// before it expires.
async function accessToken() {
  if (accessTokenCache.token && Date.now() < accessTokenCache.expiresAt) {
    return accessTokenCache.token;
  }

  const sa = serviceAccount();
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: sa.client_email,
    scope: FCM_SCOPE,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  };

  const encode = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const unsigned = `${encode(header)}.${encode(payload)}`;
  const signature = crypto
    .createSign('RSA-SHA256')
    .update(unsigned)
    .sign(sa.private_key)
    .toString('base64url');

  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${signature}`,
    }),
  });
  if (!res.ok) {
    throw new Error(`Could not get an access token (${res.status}).`);
  }
  const data = await res.json();
  accessTokenCache = {
    token: data.access_token,
    // Refresh a minute early rather than racing the expiry.
    expiresAt: Date.now() + (data.expires_in - 60) * 1000,
  };
  return data.access_token;
}

/// Sends a push. Returns true when FCM accepted it, 'STALE' when the device
/// token is no longer registered, and false on any other failure.
///
/// A failure here is reported but never breaks the action that triggered it -
/// the notification row in Postgres is the durable record.
export async function sendPush(fcmToken, { title, body, data }) {
  if (!fcmToken) return false;
  try {
    const token = await accessToken();
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId()}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: fcmToken,
            notification: { title, body },
            data: Object.fromEntries(
              Object.entries(data || {}).map(([k, v]) => [k, String(v)])
            ),
            android: {
              priority: 'HIGH',
              notification: { channel_id: 'smvec_od_updates', sound: 'default' },
            },
            apns: { payload: { aps: { sound: 'default' } } },
          },
        }),
      }
    );

    if (res.ok) return true;

    const text = await res.text().catch(() => '');
    // The app was uninstalled or reinstalled; the caller clears the token so
    // we stop trying.
    if (res.status === 404 || text.includes('UNREGISTERED') || text.includes('INVALID_ARGUMENT')) {
      return 'STALE';
    }
    console.warn('push failed:', res.status, text.slice(0, 200));
    return false;
  } catch (err) {
    console.warn('push failed:', err.message);
    return false;
  }
}
