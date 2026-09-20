import { ClerkProvider } from '@clerk/nextjs';
import './globals.css';

export const metadata = {
  title: 'SMVEC OD Management | IT Department',
  description:
    'Streamline your event On-Duty management at Sri Manakula Vinayagar Engineering College. Register events, get advisor approval, and HOD sanction in one unified platform.',
  keywords: [
    'SMVEC',
    'OD Management',
    'Event Registration',
    'College Event',
    'IT Department',
    'Sri Manakula Vinayagar Engineering College',
  ],
  authors: [{ name: 'SMVEC IT Department' }],
  openGraph: {
    title: 'SMVEC OD Management System',
    description:
      'Digital event On-Duty management for SMVEC IT Department students.',
    type: 'website',
  },
};

export default function RootLayout({ children }) {
  return (
    <ClerkProvider>
      <html lang="en">
        <head>
          <link rel="preconnect" href="https://fonts.googleapis.com" />
          <link
            rel="preconnect"
            href="https://fonts.gstatic.com"
            crossOrigin="anonymous"
          />
        </head>
        <body>{children}</body>
      </html>
    </ClerkProvider>
  );
}
