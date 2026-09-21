// Firebase Admin: verifies the ID tokens the Flutter app and the web portal
// send, and sends FCM push.
//
// The service account arrives as a single-line JSON string in
// FIREBASE_SERVICE_ACCOUNT. It never reaches the client.

import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getMessaging } from 'firebase-admin/messaging';

function serviceAccount() {
  const raw = (process.env.FIREBASE_SERVICE_ACCOUNT || '').trim().replace(/﻿/g, '');
  if (!raw) throw new Error('FIREBASE_SERVICE_ACCOUNT is not configured.');
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error('FIREBASE_SERVICE_ACCOUNT is not valid JSON.');
  }
  // Env vars often arrive with the newlines in the key escaped.
  if (typeof parsed.private_key === 'string') {
    parsed.private_key = parsed.private_key.replace(/\\n/g, '\n');
  }
  return parsed;
}

function app() {
  const existing = getApps();
  if (existing.length) return existing[0];
  const sa = serviceAccount();
  return initializeApp({
    credential: cert({
      projectId: sa.project_id,
      clientEmail: sa.client_email,
      privateKey: sa.private_key,
    }),
    projectId: sa.project_id,
  });
}

/// Verifies a Firebase ID token and returns the caller's identity.
///
/// `checkRevoked` is on so that signing out on the device, or an account being
/// disabled, takes effect immediately rather than at token expiry.
export async function verifyIdToken(idToken) {
  const decoded = await getAuth(app()).verifyIdToken(String(idToken || ''), true);
  return {
    uid: decoded.uid,
    email: (decoded.email || '').toLowerCase(),
    emailVerified: decoded.email_verified === true,
    name: decoded.name || null,
    picture: decoded.picture || null,
    // Which provider actually signed them in - used to insist students come
    // through Google rather than any provider that might be enabled later.
    signInProvider: decoded.firebase?.sign_in_provider || null,
  };
}

/// Sends a push notification. Returns true when FCM accepted it.
/// A failure here is reported but never breaks the action that triggered it.
export async function sendPush(fcmToken, { title, body, data }) {
  if (!fcmToken) return false;
  try {
    await getMessaging(app()).send({
      token: fcmToken,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data || {}).map(([k, v]) => [k, String(v)])
      ),
      android: {
        priority: 'high',
        notification: { channelId: 'smvec_od_updates', sound: 'default' },
      },
      apns: { payload: { aps: { sound: 'default' } } },
    });
    return true;
  } catch (err) {
    // An unregistered token means the app was uninstalled or reinstalled; the
    // caller clears it so we stop trying.
    const code = err?.errorInfo?.code || err?.code || '';
    if (code.includes('registration-token-not-registered') || code.includes('invalid-argument')) {
      return 'STALE';
    }
    console.warn('push failed:', code || err.message);
    return false;
  }
}
