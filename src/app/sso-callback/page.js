import { redirect } from 'next/navigation';

// Old Google sign-in callback. The portal now signs in directly, so send
// anyone with a stale link to the portal.
export default function SSOCallbackPage() {
  redirect('/app');
}
