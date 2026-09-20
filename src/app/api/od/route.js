// Retired endpoint.
//
// This route was the original OD backend. It was superseded by /api/mobile
// (see src/app/api/mobile/route.js), which both the web portal and the Flutter
// app now use, and it had no remaining callers.
//
// It is stubbed out rather than left in place because the old implementation
// was reachable without any authentication and accepted, among other things,
// an UPLOAD_FILE action that wrote caller-supplied bytes into a public storage
// bucket. The full implementation remains in git history if it is ever needed.

import { NextResponse } from 'next/server';

const GONE = {
  success: false,
  error: 'This endpoint has been retired. Use /api/mobile instead.',
};

const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

export async function OPTIONS() {
  return NextResponse.json({}, { headers });
}

export async function GET() {
  return NextResponse.json(GONE, { status: 410, headers });
}

export async function POST() {
  return NextResponse.json(GONE, { status: 410, headers });
}
