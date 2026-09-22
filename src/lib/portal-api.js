'use client';

// The portal's one way of talking to /api/v2.
//
// Two kinds of caller arrive here. A student signs in with Google and carries
// a Firebase ID token, minted fresh for every call. A staff member may instead
// have exchanged a password for a signed staff token, which the server issues
// with a twelve-hour life. The difference is confined to this file: everything
// above it just calls api().

import { idToken } from './firebase-client';

const API = '/api/v2';
const STAFF_TOKEN_KEY = 'smvec_staff_token_v3';
const STAFF_USER_KEY = 'smvec_staff_user_v3';

let staffToken = null;

/// Remembers a staff password session across reloads.
///
/// Firebase persists a student's session itself, so only this one needs
/// storing. What is kept is the signed token and the profile it resolved to -
/// never a password. Storage can throw in a private window, and a browser that
/// refuses it just means signing in again.
export function setStaffSession(token, user) {
  staffToken = token || null;
  try {
    if (token) {
      window.localStorage.setItem(STAFF_TOKEN_KEY, token);
      window.localStorage.setItem(STAFF_USER_KEY, JSON.stringify(user || null));
    } else {
      window.localStorage.removeItem(STAFF_TOKEN_KEY);
      window.localStorage.removeItem(STAFF_USER_KEY);
    }
  } catch {
    // Not fatal: the session lives in memory for this tab either way.
  }
}

export function loadStaffSession() {
  try {
    const token = window.localStorage.getItem(STAFF_TOKEN_KEY);
    if (!token) return null;
    staffToken = token;
    const raw = window.localStorage.getItem(STAFF_USER_KEY);
    return { token, user: raw ? JSON.parse(raw) : null };
  } catch {
    return null;
  }
}

export function clearStaffSession() {
  setStaffSession(null, null);
}

export const hasStaffSession = () => Boolean(staffToken);

/// One POST per call.
///
/// A student's ID token is fetched here rather than passed in, and an expired
/// one is re-minted and retried once - a session that aged out in another tab
/// should not look like a failure. A staff token cannot be refreshed, so a 401
/// on that route is final and the caller signs in again.
export async function api(action, payload = {}, { authenticated = true, retried = false } = {}) {
  let token = null;
  if (authenticated) {
    token = staffToken || (await idToken(retried));
    if (!token) {
      throw Object.assign(new Error('You are not signed in. Please sign in again.'), { status: 401 });
    }
  }

  let res;
  try {
    res = await fetch(API, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify({ action, payload }),
    });
  } catch {
    throw Object.assign(new Error('Could not reach the server. Check your connection.'), { status: 0 });
  }

  let data;
  try {
    data = await res.json();
  } catch {
    throw Object.assign(new Error(`Unexpected server response (${res.status}).`), { status: res.status });
  }

  if (res.status === 401 && authenticated && !retried && !staffToken) {
    return api(action, payload, { authenticated, retried: true });
  }
  if (!res.ok || data.success !== true) {
    throw Object.assign(new Error(data.error || 'Something went wrong.'), { status: res.status });
  }
  return data;
}

/// Calls that work before anyone is signed in, such as the class list.
export const apiPublic = (action, payload = {}) =>
  api(action, payload, { authenticated: false });
