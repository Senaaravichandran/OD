// Clerk request handler.
//
// In Next.js 16 the `middleware` file convention was renamed to `proxy`, so
// Clerk's handler lives here rather than in middleware.js. Every route stays
// public: the portal decides what to show from the client-side Clerk session,
// and /api/mobile verifies the Clerk token itself, so there is nothing to gate
// at this layer. This file exists so Clerk's server helpers and <ClerkProvider>
// can read the session off the incoming request.

import { clerkMiddleware } from '@clerk/nextjs/server';

export default clerkMiddleware();

export const config = {
  matcher: [
    // Everything except Next internals and static files, plus all API routes.
    '/((?!_next|[^?]*\\.(?:html?|css|js(?!on)|jpe?g|webp|png|gif|svg|ttf|woff2?|ico|csv|docx?|xlsx?|zip|webmanifest|apk)).*)',
    '/(api|trpc)(.*)',
  ],
};
