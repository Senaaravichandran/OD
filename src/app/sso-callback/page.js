import { AuthenticateWithRedirectCallback } from '@clerk/nextjs';

export default function SSOCallbackPage() {
  return (
    <div style={{ display: 'flex', minHeight: '100vh', alignItems: 'center', justifyContent: 'center', background: '#f8fafc' }}>
      <div style={{ textAlign: 'center' }}>
        <div style={{ width: '40px', height: '40px', border: '4px solid #3350B0', borderTopColor: 'transparent', borderRadius: '50%', animation: 'spin 1s linear infinite', margin: '0 auto 16px' }}></div>
        <p style={{ color: '#475569', fontWeight: 600 }}>Completing SMVEC Institutional Sign-In...</p>
      </div>
      <AuthenticateWithRedirectCallback signInForceRedirectUrl="/app" signUpForceRedirectUrl="/app" />
    </div>
  );
}
