// Supabase Storage, over its REST API.
//
// The bucket is private and only the service role touches it, so uploads and
// downloads both go through the server. A phone never holds a key that can
// write to storage, and an object key on its own is not enough to read a file.

import crypto from 'crypto';

const BUCKET = 'od-files';

const clean = (v) =>
  (v == null ? '' : String(v)).trim().replace(/^["']|["']$/g, '').replace(/﻿/g, '');

function config() {
  const url = clean(process.env.SUPABASE_URL) || clean(process.env.NEXT_PUBLIC_SUPABASE_URL);
  const key = clean(process.env.SUPABASE_SERVICE_ROLE_KEY);
  if (!url) throw new Error('SUPABASE_URL is not configured.');
  if (!key) throw new Error('SUPABASE_SERVICE_ROLE_KEY is not configured.');
  return { url: url.replace(/\/$/, ''), key };
}

/// True when file storage is set up. Lets the API report a clear message
/// instead of failing mid-upload.
export function storageConfigured() {
  try {
    config();
    return true;
  } catch {
    return false;
  }
}

const EXTENSIONS = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'application/pdf': 'pdf',
};

export const ALLOWED_MIME = Object.keys(EXTENSIONS);
export const MAX_BYTES = 10 * 1024 * 1024;

/// Builds the object key for a file. Grouping by request id means everything
/// belonging to one OD can be found - and deleted - together.
export function objectKeyFor({ odRequestId, kind, mimeType }) {
  const ext = EXTENSIONS[mimeType] || 'bin';
  return `od/${odRequestId}/${kind.toLowerCase()}/${crypto.randomUUID()}.${ext}`;
}

/// Uploads bytes. Throws with a readable message on failure.
export async function uploadObject({ objectKey, bytes, mimeType }) {
  const { url, key } = config();
  const res = await fetch(`${url}/storage/v1/object/${BUCKET}/${objectKey}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': mimeType,
      'x-upsert': 'false',
    },
    body: bytes,
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(`Upload failed (${res.status}): ${detail.slice(0, 160)}`);
  }
  return objectKey;
}

/// A short-lived URL for viewing one file. Regenerated on every request rather
/// than stored, so access cannot outlive the caller's permission to look.
export async function signedUrl(objectKey, expiresInSeconds = 300) {
  const { url, key } = config();
  const res = await fetch(`${url}/storage/v1/object/sign/${BUCKET}/${objectKey}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ expiresIn: expiresInSeconds }),
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(`Could not sign the file URL (${res.status}): ${detail.slice(0, 160)}`);
  }
  const data = await res.json();
  // The API returns a path relative to /storage/v1.
  return `${url}/storage/v1${data.signedURL || data.signedUrl}`;
}

export async function deleteObject(objectKey) {
  try {
    const { url, key } = config();
    await fetch(`${url}/storage/v1/object/${BUCKET}/${objectKey}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${key}` },
    });
  } catch (err) {
    // Losing a file is not worth failing the request that removed its record.
    console.warn('could not delete stored object:', err.message);
  }
}
