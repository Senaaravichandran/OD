'use client';

// Firebase in the browser, for the web portal.
//
// Only public configuration lives here - the same values that ship inside the
// Android APK. Nothing that can act on its own behalf: the portal gets an ID
// token and the server decides what it is allowed to do.

import { initializeApp, getApps } from 'firebase/app';
import {
  GoogleAuthProvider,
  getAuth,
  onAuthStateChanged,
  signInWithPopup,
  signOut as fbSignOut,
} from 'firebase/auth';

const config = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_SENDER_ID,
};

export function firebaseReady() {
  return Boolean(config.apiKey && config.authDomain && config.projectId);
}

function app() {
  if (!firebaseReady()) throw new Error('Firebase is not configured for the web portal.');
  return getApps().length ? getApps()[0] : initializeApp(config);
}

export function auth() {
  return getAuth(app());
}

/// Google sign-in, restricted to the college domain.
///
/// `hd` nudges Google's own picker towards college accounts; the rule that
/// actually matters is enforced by the server against the verified address.
export async function signInWithGoogle() {
  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({ hd: 'smvec.ac.in', prompt: 'select_account' });
  const result = await signInWithPopup(auth(), provider);
  return result.user;
}

export async function signOut() {
  await fbSignOut(auth());
}

/// The ID token the API needs. `force` re-mints it, which matters right after
/// a profile change so the server sees current claims.
export async function idToken(force = false) {
  const user = auth().currentUser;
  if (!user) return null;
  try {
    return await user.getIdToken(force);
  } catch {
    return null;
  }
}

export function watchAuth(callback) {
  return onAuthStateChanged(auth(), callback);
}

/// Turns Firebase's codes into something a student can act on.
export function describeAuthError(err) {
  const code = err?.code || '';
  if (code.includes('popup-closed-by-user') || code.includes('cancelled-popup-request')) {
    return null; // they simply changed their mind
  }
  if (code.includes('popup-blocked')) {
    return 'Your browser blocked the sign-in window. Allow pop-ups for this site and try again.';
  }
  if (code.includes('network-request-failed')) {
    return 'No internet connection. Check your network and try again.';
  }
  if (code.includes('operation-not-allowed') || code.includes('configuration-not-found')) {
    return 'Google sign-in is not enabled for this site yet. Contact the department.';
  }
  if (code.includes('unauthorized-domain')) {
    return 'This website is not authorised for sign-in yet. Contact the department.';
  }
  return err?.message || 'Sign-in failed. Please try again.';
}
