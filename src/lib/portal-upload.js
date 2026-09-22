'use client';

// Picking, shrinking and uploading a certificate or a photograph, matching
// what the Android app does so a file looks the same whichever way it arrived.
//
// Compression happens in the browser before anything leaves it. A phone photo
// pulled off a laptop is still eight to twelve megabytes, the department's
// connection is not, and the server refuses anything over ten. A file the
// browser cannot decode is sent as it is rather than lost - compression is a
// convenience, not a gate.

import { api } from './portal-api';

export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;
export const MAX_DIMENSION = 1600;
export const QUALITY = 0.8;

export const FILE_KINDS = [
  { kind: 'CERTIFICATE', label: 'Certificate' },
  { kind: 'EVENT_PHOTO', label: 'Photo from the event' },
  { kind: 'WINNING_PHOTO', label: 'Prize photo' },
  { kind: 'SUPPORTING_DOCUMENT', label: 'Supporting document' },
];

export const kindLabel = (kind) =>
  FILE_KINDS.find((k) => k.kind === kind)?.label || 'Attachment';

const ALLOWED = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];

export const humanSize = (bytes) => (bytes < 1024 * 1024
  ? `${Math.round(bytes / 1024)} KB`
  : `${(bytes / (1024 * 1024)).toFixed(1)} MB`);

/// Draws the image into a canvas no larger than [max] on its long edge and
/// re-encodes it as JPEG. Returns null if the browser cannot decode the file,
/// which is the caller's signal to send the original.
async function shrink(file, max, quality) {
  if (typeof createImageBitmap !== 'function') return null;
  let bitmap;
  try {
    bitmap = await createImageBitmap(file);
  } catch {
    return null;
  }

  const scale = Math.min(1, max / Math.max(bitmap.width, bitmap.height));
  const width = Math.round(bitmap.width * scale);
  const height = Math.round(bitmap.height * scale);

  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  if (!ctx) {
    bitmap.close?.();
    return null;
  }
  ctx.drawImage(bitmap, 0, 0, width, height);
  bitmap.close?.();

  const blob = await new Promise((resolve) => {
    canvas.toBlob(resolve, 'image/jpeg', quality);
  });
  return blob || null;
}

const toBase64 = (blob) => new Promise((resolve, reject) => {
  const reader = new FileReader();
  reader.onerror = () => reject(new Error('The file could not be read.'));
  reader.onload = () => {
    const result = String(reader.result || '');
    // A data URL, so drop the "data:...;base64," prefix the API does not want.
    resolve(result.slice(result.indexOf(',') + 1));
  };
  reader.readAsDataURL(blob);
});

/// Compresses [file] if it is an image, then uploads it against [requestId].
///
/// [onStep] reports what is happening, because shrinking a large photograph
/// takes a noticeable moment and a silent button looks broken.
export async function uploadFile({ requestId, kind, file, onStep }) {
  const isPdf = file.type === 'application/pdf';

  let blob = file;
  let fileName = file.name;
  let mimeType = file.type;

  if (!isPdf) {
    onStep?.('Shrinking the image…');
    const first = await shrink(file, MAX_DIMENSION, QUALITY);
    if (first) {
      blob = first;
      mimeType = 'image/jpeg';
      fileName = `${file.name.replace(/\.[^.]+$/, '')}.jpg`;

      // Still too big: one harder pass rather than refusing outright.
      if (blob.size > MAX_UPLOAD_BYTES) {
        const second = await shrink(file, 1200, 0.6);
        if (second && second.size < blob.size) blob = second;
      }
    }
  }

  if (!ALLOWED.includes(mimeType)) {
    throw new Error('Only JPEG, PNG or WebP images, or PDF files, can be attached.');
  }
  if (blob.size > MAX_UPLOAD_BYTES) {
    throw new Error(`That file is ${humanSize(blob.size)}, over the 10 MB limit.`);
  }

  onStep?.('Uploading…');
  const res = await api('UPLOAD_FILE', {
    reqId: requestId,
    kind,
    fileName: fileName.slice(0, 120),
    mimeType,
    data: await toBase64(blob),
  });
  return res.file;
}

/// A five-minute signed URL for one file. Nothing in the bucket has a public
/// address, so this is the only way to see it.
export async function fileUrl(fileId) {
  const res = await api('FILE_URL', { fileId });
  return res.url;
}

export async function deleteFile(fileId) {
  await api('DELETE_FILE', { fileId });
}

/// The bytes behind a file, for embedding a photograph in an export.
export async function fileBytes(fileId) {
  const url = await fileUrl(fileId);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Could not download the file (${res.status}).`);
  return new Uint8Array(await res.arrayBuffer());
}
