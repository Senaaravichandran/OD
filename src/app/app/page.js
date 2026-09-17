'use client';

import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import { useClerk, useUser, useSignIn } from '@clerk/nextjs';
import styles from './app.module.css';

export default function AppPortal() {
  const clerk = useClerk();
  const { isLoaded: clerkLoaded, isSignedIn: clerkSignedIn, user: clerkUser } = useUser();
  const { isLoaded: signInLoaded, signIn } = useSignIn();

  // Current Authenticated User State: { name, email, role: 'STUDENT' | 'ADVISOR' | 'HOD', rollNumber, year, section }
  const [user, setUser] = useState(null);

  // Live State from Upstash Redis
  const [requests, setRequests] = useState([]);
  const [auditLogs, setAuditLogs] = useState([]);
  const [notifications, setNotifications] = useState([]);
  const [loading, setLoading] = useState(true);
  const [servicesStatus, setServicesStatus] = useState({ redis: true, supabase: true, resend: true, clerk: true });
  const [showNotifDrawer, setShowNotifDrawer] = useState(false);

  // Auth Form State (Only @smvec.ac.in permitted)
  const [authRoleTab, setAuthRoleTab] = useState('STUDENT'); // 'STUDENT' | 'ADVISOR' | 'HOD'
  const [authEmail, setAuthEmail] = useState('');
  const [authPassword, setAuthPassword] = useState('');
  const [authName, setAuthName] = useState('');
  const [authRoll, setAuthRoll] = useState('');
  const [authYear, setAuthYear] = useState('3');
  const [authSection, setAuthSection] = useState('A');
  const [authError, setAuthError] = useState('');
  const [authSuccess, setAuthSuccess] = useState('');

  // Forgot Password Modal State (Strictly for Staff/Advisor & HOD via Resend)
  const [showForgotModal, setShowForgotModal] = useState(false);
  const [forgotRole, setForgotRole] = useState('ADVISOR');
  const [forgotEmail, setForgotEmail] = useState('');
  const [forgotOtp, setForgotOtp] = useState('');
  const [forgotStep, setForgotStep] = useState(1); // 1 = Enter email, 2 = Enter OTP, 3 = Verified
  const [forgotLoading, setForgotLoading] = useState(false);
  const [forgotError, setForgotError] = useState('');

  // Modals & Navigation
  const [showNewODModal, setShowNewODModal] = useState(false);
  const [showReviewModal, setShowReviewModal] = useState(null); // request to review
  const [showResultModal, setShowResultModal] = useState(null); // request to add result
  const [advisorFilter, setAdvisorFilter] = useState('ALL'); // 'ALL' | 'PENDING' | 'APPROVED_BY_ME' | 'REJECTED'
  const [hodTab, setHodTab] = useState('PENDING'); // 'PENDING' | 'APPROVED' | 'AUDIT'

  // New OD Form State (Clean inputs - NO watermark)
  const [formData, setFormData] = useState({
    submissionType: 'SOLO',
    eventType: 'Hackathon',
    eventName: '',
    eventDate: '',
    eventDay: '',
    description: '',
    teamMembers: [],
  });
  const [selectedFile, setSelectedFile] = useState(null);
  const [formError, setFormError] = useState('');

  // Review Remarks
  const [reviewRemarks, setReviewRemarks] = useState('');

  // Result Form State
  const [resultData, setResultData] = useState({
    status: 'WON',
    projectName: '',
    description: '',
  });
  const [resultFile, setResultFile] = useState(null);

  // Fetch live state on mount
  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      const res = await fetch('/api/od');
      const json = await res.json();
      if (json.success && json.data) {
        setRequests(json.data.requests || []);
        setAuditLogs(json.data.auditLogs || []);
        setNotifications(json.data.notifications || []);
        if (json.connectedServices) {
          setServicesStatus(json.connectedServices);
        }
      }
    } catch (e) {
      console.error('Failed to load live data:', e);
    } finally {
      setLoading(false);
    }
  };

  const callApi = async (action, payload) => {
    try {
      const res = await fetch('/api/od', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action, payload }),
      });
      const json = await res.json();
      if (json.success && json.data) {
        setRequests(json.data.requests);
        setAuditLogs(json.data.auditLogs);
        setNotifications(json.data.notifications);
      }
      return json;
    } catch (e) {
      console.error('API call failed:', e);
      return { success: false, error: e.message };
    }
  };

  // Calculate day of week on date change
  const handleDateChange = (e) => {
    const val = e.target.value;
    if (!val) {
      setFormData({ ...formData, eventDate: '', eventDay: '' });
      return;
    }
    const d = new Date(val);
    const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    setFormData({
      ...formData,
      eventDate: val,
      eventDay: days[d.getDay()] || '',
    });
  };

  // -------------------------------------------------------------
  // AUTHENTICATION LOGIC (STRICT @smvec.ac.in ONLY)
  // -------------------------------------------------------------
  const validateSmvecDomain = (email) => {
    return email && email.trim().toLowerCase().endsWith('@smvec.ac.in');
  };

  const handleLogin = async (e) => {
    e.preventDefault();
    setAuthError('');
    setAuthSuccess('');

    const cleanEmail = authEmail.trim().toLowerCase();

    // 1. Mandatory @smvec.ac.in check
    if (!validateSmvecDomain(cleanEmail)) {
      setAuthError('Access Denied: Only official college email addresses ending in @smvec.ac.in are permitted.');
      return;
    }

    const res = await callApi('LOGIN_USER', {
      role: authRoleTab,
      email: cleanEmail,
      password: authPassword,
      name: authName.trim(),
      rollNumber: authRoll.trim().toUpperCase(),
      year: Number(authYear),
      section: authSection,
    });

    if (res.success && res.user) {
      setUser(res.user);
    } else {
      setAuthError(res.error || 'Authentication failed. Please verify your credentials.');
    }
  };

  // Clerk Google Workspace Auth Synchronization (@smvec.ac.in enforced)
  useEffect(() => {
    if (clerkLoaded && clerkSignedIn && clerkUser && !user) {
      const primaryEmail = clerkUser.primaryEmailAddress?.emailAddress?.toLowerCase() || '';
      if (!validateSmvecDomain(primaryEmail)) {
        setAuthError(`Access Denied: Google account (${primaryEmail}) is not an @smvec.ac.in institutional account. Please sign out and use your official college Google account.`);
        if (clerk?.signOut) clerk.signOut();
        return;
      }

      const role = (authRoleTab || 'STUDENT').toUpperCase();
      const rollMatch = primaryEmail.match(/\d+[a-zA-Z]+\d+/);
      const defaultRoll = rollMatch ? rollMatch[0].toUpperCase() : '21IT101';

      setUser({
        name: clerkUser.fullName || primaryEmail.split('@')[0].toUpperCase(),
        email: primaryEmail,
        role: role,
        rollNumber: defaultRoll,
        department: 'Information Technology',
        year: 3,
        section: 'A',
      });
      setAuthError('');
    }
  }, [clerkLoaded, clerkSignedIn, clerkUser, user, authRoleTab, clerk]);

  // Real Clerk Google Sign-In
  const handleGoogleSignIn = async () => {
    setAuthError('');
    try {
      if (signIn) {
        await signIn.authenticateWithRedirect({
          strategy: 'oauth_google',
          redirectUrl: '/sso-callback',
          redirectUrlComplete: '/app',
        });
        return;
      }
      if (clerk?.openSignIn) {
        clerk.openSignIn();
        return;
      }
    } catch (err) {
      console.error('Clerk Google Auth error:', err);
      if (clerk?.openSignIn) {
        clerk.openSignIn();
      } else {
        setAuthError(err.message || 'Google Authentication failed. Please try again.');
      }
    }
  };

  // -------------------------------------------------------------
  // FORGOT PASSWORD (STRICTLY FOR STAFF & HOD VIA RESEND)
  // -------------------------------------------------------------
  const handleRequestForgotOtp = async (e) => {
    e.preventDefault();
    setForgotError('');
    if (!validateSmvecDomain(forgotEmail)) {
      setForgotError('Please enter a valid @smvec.ac.in email address.');
      return;
    }

    setForgotLoading(true);
    const res = await callApi('FORGOT_PASSWORD', {
      email: forgotEmail.trim().toLowerCase(),
      role: forgotRole,
    });
    setForgotLoading(false);

    if (res.success) {
      setForgotStep(2);
    } else {
      setForgotError(res.error || 'Failed to dispatch verification email. Please try again.');
    }
  };

  const handleVerifyForgotOtp = async (e) => {
    e.preventDefault();
    setForgotError('');
    if (!forgotOtp.trim()) {
      setForgotError('Please enter the 6-digit verification code.');
      return;
    }

    setForgotLoading(true);
    const res = await callApi('VERIFY_OTP', {
      email: forgotEmail.trim().toLowerCase(),
      otp: forgotOtp.trim(),
    });
    setForgotLoading(false);

    if (res.success) {
      setForgotStep(3);
    } else {
      setForgotError(res.error || 'Invalid verification code.');
    }
  };

  // -------------------------------------------------------------
  // SUBMIT NEW OD (STUDENT)
  // -------------------------------------------------------------
  const handleCreateOD = async (e) => {
    e.preventDefault();
    setFormError('');

    if (!formData.eventName.trim()) {
      setFormError('Please enter the event name.');
      return;
    }
    if (!formData.eventDate) {
      setFormError('Please select the event date.');
      return;
    }
    if (!formData.description.trim()) {
      setFormError('Please provide a description of the OD purpose.');
      return;
    }

    const docName = selectedFile ? selectedFile.name : 'Event_Invitation_Letter.pdf';

    await callApi('CREATE_OD', {
      studentName: user.name,
      studentEmail: user.email,
      rollNumber: user.rollNumber,
      department: user.department,
      year: user.year,
      section: user.section,
      submissionType: formData.submissionType,
      teamMembers: formData.submissionType === 'TEAM' ? formData.teamMembers : [],
      eventType: formData.eventType,
      eventName: formData.eventName.trim(),
      eventDate: formData.eventDate,
      eventDay: formData.eventDay,
      description: formData.description.trim(),
      attachmentName: docName,
    });

    setShowNewODModal(false);
    setSelectedFile(null);
    setFormData({
      submissionType: 'SOLO',
      eventType: 'Hackathon',
      eventName: '',
      eventDate: '',
      eventDay: '',
      description: '',
      teamMembers: [],
    });
  };

  // -------------------------------------------------------------
  // ADVISOR APPROVE / REJECT
  // -------------------------------------------------------------
  const handleAdvisorApprove = async (reqId) => {
    const remarks = reviewRemarks.trim() || 'Verified student eligibility and academic attendance. Approved and recommended for HOD sanction.';
    await callApi('ADVISOR_APPROVE', {
      reqId,
      remarks,
      advisorName: user.name,
    });
    setShowReviewModal(null);
    setReviewRemarks('');
  };

  const handleAdvisorReject = async (reqId) => {
    const remarks = reviewRemarks.trim() || 'Dates clash with scheduled internal examinations / Attendance requirement not satisfied.';
    await callApi('ADVISOR_REJECT', {
      reqId,
      remarks,
      advisorName: user.name,
    });
    setShowReviewModal(null);
    setReviewRemarks('');
  };

  // -------------------------------------------------------------
  // HOD SANCTION / REJECT (CONFIRMATION MAIL TO STUDENT DISPATCHED IF ADVISOR APPROVED)
  // -------------------------------------------------------------
  const handleHodApprove = async (reqId) => {
    const remarks = reviewRemarks.trim() || 'Officially approved with college attendance compensation.';
    await callApi('HOD_APPROVE', {
      reqId,
      remarks,
      hodName: user.name,
    });
    setShowReviewModal(null);
    setReviewRemarks('');
  };

  const handleHodReject = async (reqId) => {
    const remarks = reviewRemarks.trim() || 'Department quota exceeded / Event not aligned with curriculum priorities.';
    await callApi('HOD_REJECT', {
      reqId,
      remarks,
      hodName: user.name,
    });
    setShowReviewModal(null);
    setReviewRemarks('');
  };

  // -------------------------------------------------------------
  // SUBMIT RESULT
  // -------------------------------------------------------------
  const handleSaveResult = async (e) => {
    e.preventDefault();
    if (!showResultModal) return;

    await callApi('SUBMIT_RESULT', {
      reqId: showResultModal.id,
      studentName: user.name,
      status: resultData.status,
      projectName: resultData.projectName.trim() || showResultModal.eventName,
      description: resultData.description.trim(),
      certificateName: resultFile ? resultFile.name : `Certificate_${showResultModal.id}.pdf`,
    });

    setShowResultModal(null);
    setResultFile(null);
    setResultData({ status: 'WON', projectName: '', description: '' });
  };

  // Export CSV Report
  const handleExportCSV = () => {
    const headers = ['OD_ID', 'Student_Name', 'Roll_No', 'Year', 'Section', 'Event_Type', 'Event_Name', 'Event_Date', 'Status', 'Advisor_Approval', 'HOD_Sanction'];
    const rows = requests.map((r) => [
      r.id,
      `"${r.studentName}"`,
      r.rollNumber,
      r.year,
      r.section,
      r.eventType,
      `"${r.eventName}"`,
      r.eventDate,
      r.status,
      r.advisorName ? `Approved (${r.advisorName})` : 'Pending Advisor',
      r.hodName ? `Sanctioned (${r.hodName})` : 'Pending HOD',
    ]);
    const csvContent = 'data:text/csv;charset=utf-8,' + [headers.join(','), ...rows.map((e) => e.join(','))].join('\n');
    const encodedUri = encodeURI(csvContent);
    const link = document.createElement('a');
    link.setAttribute('href', encodedUri);
    link.setAttribute('download', `SMVEC_IT_OD_Report_${new Date().toISOString().slice(0, 10)}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  // -------------------------------------------------------------
  // RENDER: LOGIN VIEW (IF UNAUTHENTICATED)
  // -------------------------------------------------------------
  if (!user) {
    return (
      <div className={styles.appContainer}>
        {/* Top Navbar */}
        <header className={styles.topNav}>
          <div className={styles.topNavInner}>
            <Link href="/" className={styles.brandGroup}>
              <img src="/college_logo.png" alt="SMVEC Logo" className={styles.brandLogo} />
              <div className={styles.brandInfo}>
                <span className={styles.brandTitle}>SMVEC ON-DUTY SYSTEM</span>
                <span className={styles.brandSubtitle}>Department of Information Technology</span>
              </div>
            </Link>
            <div className={styles.navActions}>
              <a href="/downloads/smvec-od.apk" download="smvec-od.apk" className={styles.navLinkBtn}>
                📱 Download Real APK (~45.7 MB)
              </a>
              <Link href="/" className={styles.navLinkBtn}>
                ← Back to Landing Page
              </Link>
            </div>
          </div>
        </header>

        {/* Institutional Domain Banner */}
        <div style={{ background: '#f8fafc', borderBottom: '1px solid #e2e8f0', padding: '10px 24px', textAlign: 'center', fontSize: '0.8rem', color: '#475569' }}>
          🔒 <strong>Institutional Security:</strong> Access is restricted strictly to verified <strong>@smvec.ac.in</strong> email accounts.
        </div>

        {/* Login Container */}
        <div className={styles.authContainer}>
          <div className={styles.authCard} style={{ maxWidth: '460px', width: '100%' }}>
            <div style={{ textAlign: 'center', marginBottom: '20px' }}>
              <img src="/college_logo.png" alt="SMVEC Logo" className={styles.authHeaderLogo} />
              <h1 className={styles.authTitle} style={{ fontSize: '1.4rem' }}>Portal Authentication</h1>
              <p className={styles.authSubtitle} style={{ fontSize: '0.82rem' }}>
                Select your institutional role to proceed
              </p>
            </div>

            {/* Role Tabs */}
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '6px', marginBottom: '20px', background: '#f1f5f9', padding: '4px', borderRadius: '10px' }}>
              <button
                type="button"
                className={`${styles.roleTab} ${authRoleTab === 'STUDENT' ? styles.roleTabActive : ''}`}
                style={{ padding: '8px 4px', fontSize: '0.78rem' }}
                onClick={() => {
                  setAuthRoleTab('STUDENT');
                  setAuthError('');
                  setAuthPassword('');
                }}
              >
                🎓 Student
              </button>
              <button
                type="button"
                className={`${styles.roleTab} ${authRoleTab === 'ADVISOR' ? styles.roleTabActive : ''}`}
                style={{ padding: '8px 4px', fontSize: '0.78rem' }}
                onClick={() => {
                  setAuthRoleTab('ADVISOR');
                  setAuthError('');
                  setAuthPassword('');
                }}
              >
                👩‍🏫 Staff / Advisor
              </button>
              <button
                type="button"
                className={`${styles.roleTab} ${authRoleTab === 'HOD' ? styles.roleTabActive : ''}`}
                style={{ padding: '8px 4px', fontSize: '0.78rem' }}
                onClick={() => {
                  setAuthRoleTab('HOD');
                  setAuthError('');
                  setAuthPassword('');
                }}
              >
                👨‍💼 HOD
              </button>
            </div>

            {/* Error Message Display */}
            {authError && (
              <div style={{ background: '#fef2f2', border: '1px solid #fecaca', borderRadius: '8px', padding: '10px 14px', marginBottom: '16px', color: '#b91c1c', fontSize: '0.82rem', lineHeight: '1.4' }}>
                {authError}
              </div>
            )}

            {/* Google Workspace Auth Button (@smvec.ac.in) */}
            <button
              type="button"
              onClick={handleGoogleSignIn}
              style={{
                width: '100%',
                padding: '11px',
                background: '#ffffff',
                border: '1px solid #cbd5e1',
                borderRadius: '8px',
                color: '#1e293b',
                fontWeight: '600',
                fontSize: '0.86rem',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '10px',
                cursor: 'pointer',
                boxShadow: '0 1px 3px rgba(0,0,0,0.05)',
                marginBottom: '18px',
              }}
            >
              <svg width="18" height="18" viewBox="0 0 24 24">
                <path fill="#4285F4" d="M23.745 12.27c0-.7-.06-1.4-.19-2.07H12v4.51h6.6c-.29 1.52-1.14 2.82-2.4 3.68v3.05h3.88c2.27-2.09 3.665-5.17 3.665-9.17z"/>
                <path fill="#34A853" d="M12 24c3.24 0 5.95-1.08 7.93-2.91l-3.88-3.05c-1.08.72-2.45 1.16-4.05 1.16-3.12 0-5.77-2.1-6.72-4.93H1.25v3.15C3.26 21.36 7.33 24 12 24z"/>
                <path fill="#FBBC05" d="M5.28 14.27c-.25-.72-.38-1.49-.38-2.27s.13-1.55.38-2.27V6.58H1.25C.45 8.18 0 9.99 0 12s.45 3.82 1.25 5.42l4.03-3.15z"/>
                <path fill="#EA4335" d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.95 1.19 15.24 0 12 0 7.33 0 3.26 2.64 1.25 6.58l4.03 3.15c.95-2.83 3.6-4.98 6.72-4.98z"/>
              </svg>
              Continue with Google (@smvec.ac.in)
            </button>

            <div style={{ display: 'flex', alignItems: 'center', margin: '14px 0', gap: '10px' }}>
              <div style={{ flex: 1, height: '1px', background: '#e2e8f0' }} />
              <span style={{ fontSize: '0.72rem', color: '#94a3b8', textTransform: 'uppercase', letterSpacing: '0.5px' }}>Or Institutional Email</span>
              <div style={{ flex: 1, height: '1px', background: '#e2e8f0' }} />
            </div>

            {/* Role-Specific Form */}
            <form onSubmit={handleLogin}>
              <div className={styles.formGroup} style={{ marginBottom: '14px' }}>
                <label className={styles.formLabel}>College Email ID (@smvec.ac.in)</label>
                <input
                  type="email"
                  className={styles.formInput}
                  value={authEmail}
                  onChange={(e) => setAuthEmail(e.target.value)}
                  placeholder={authRoleTab === 'STUDENT' ? 'rollnumber@smvec.ac.in' : authRoleTab === 'ADVISOR' ? 'staff@smvec.ac.in' : 'hod.it@smvec.ac.in'}
                  required
                />
              </div>

              {/* STUDENT FIELDS */}
              {authRoleTab === 'STUDENT' && (
                <>
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px', marginBottom: '14px' }}>
                    <div className={styles.formGroup}>
                      <label className={styles.formLabel}>Roll Number</label>
                      <input
                        type="text"
                        className={styles.formInput}
                        value={authRoll}
                        onChange={(e) => setAuthRoll(e.target.value)}
                        placeholder="e.g. 21IT101"
                        required
                      />
                    </div>
                    <div className={styles.formGroup}>
                      <label className={styles.formLabel}>Full Name</label>
                      <input
                        type="text"
                        className={styles.formInput}
                        value={authName}
                        onChange={(e) => setAuthName(e.target.value)}
                        placeholder="Student Name"
                        required
                      />
                    </div>
                  </div>

                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px', marginBottom: '18px' }}>
                    <div className={styles.formGroup}>
                      <label className={styles.formLabel}>Academic Year</label>
                      <select className={styles.formInput} value={authYear} onChange={(e) => setAuthYear(e.target.value)}>
                        <option value="1">1st Year</option>
                        <option value="2">2nd Year</option>
                        <option value="3">3rd Year</option>
                        <option value="4">4th Year</option>
                      </select>
                    </div>
                    <div className={styles.formGroup}>
                      <label className={styles.formLabel}>Section</label>
                      <select className={styles.formInput} value={authSection} onChange={(e) => setAuthSection(e.target.value)}>
                        <option value="A">Section A</option>
                        <option value="B">Section B</option>
                        <option value="C">Section C</option>
                      </select>
                    </div>
                  </div>
                </>
              )}

              {/* STAFF / ADVISOR PASSWORD FIELD */}
              {authRoleTab === 'ADVISOR' && (
                <div className={styles.formGroup} style={{ marginBottom: '14px' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <label className={styles.formLabel}>Staff Password</label>
                    <button
                      type="button"
                      onClick={() => {
                        setForgotRole('ADVISOR');
                        setForgotEmail(authEmail || '');
                        setForgotStep(1);
                        setForgotError('');
                        setShowForgotModal(true);
                      }}
                      style={{ background: 'none', border: 'none', color: '#3350b0', fontSize: '0.74rem', cursor: 'pointer', textDecoration: 'underline' }}
                    >
                      Forgot Password?
                    </button>
                  </div>
                  <input
                    type="password"
                    className={styles.formInput}
                    value={authPassword}
                    onChange={(e) => setAuthPassword(e.target.value)}
                    placeholder="Enter staff password"
                    required
                  />
                </div>
              )}

              {/* HOD PASSWORD FIELD */}
              {authRoleTab === 'HOD' && (
                <div className={styles.formGroup} style={{ marginBottom: '14px' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <label className={styles.formLabel}>HOD Password</label>
                    <button
                      type="button"
                      onClick={() => {
                        setForgotRole('HOD');
                        setForgotEmail(authEmail || '');
                        setForgotStep(1);
                        setForgotError('');
                        setShowForgotModal(true);
                      }}
                      style={{ background: 'none', border: 'none', color: '#3350b0', fontSize: '0.74rem', cursor: 'pointer', textDecoration: 'underline' }}
                    >
                      Forgot Password?
                    </button>
                  </div>
                  <input
                    type="password"
                    className={styles.formInput}
                    value={authPassword}
                    onChange={(e) => setAuthPassword(e.target.value)}
                    placeholder="Enter HOD password"
                    required
                  />
                </div>
              )}

              <button type="submit" className={styles.authSubmitBtn} style={{ width: '100%', marginTop: '8px' }}>
                Sign In as {authRoleTab === 'STUDENT' ? 'Student' : authRoleTab === 'ADVISOR' ? 'Class Advisor' : 'HOD'} →
              </button>
            </form>
          </div>
        </div>

        {/* ========================================================= */}
        {/* FORGOT PASSWORD MODAL (STRICTLY FOR STAFF & HOD VIA RESEND) */}
        {/* ========================================================= */}
        {showForgotModal && (
          <div className={styles.modalBackdrop}>
            <div className={styles.modalBox} style={{ maxWidth: '420px' }}>
              <div className={styles.modalHeader}>
                <h3 className={styles.modalTitle}>
                  🔑 {forgotRole === 'HOD' ? 'HOD' : 'Staff'} Password Recovery
                </h3>
                <button className={styles.closeModalBtn} onClick={() => setShowForgotModal(false)}>
                  ✕
                </button>
              </div>

              {forgotError && (
                <div style={{ background: '#fef2f2', border: '1px solid #fecaca', borderRadius: '6px', padding: '10px', marginBottom: '14px', color: '#b91c1c', fontSize: '0.8rem' }}>
                  {forgotError}
                </div>
              )}

              {/* STEP 1: Enter Email to Dispatch Resend OTP */}
              {forgotStep === 1 && (
                <form onSubmit={handleRequestForgotOtp}>
                  <p style={{ fontSize: '0.84rem', color: '#4b5563', marginBottom: '14px' }}>
                    Enter your official <strong>@smvec.ac.in</strong> email address. A 6-digit security code will be dispatched via <strong>Resend</strong>.
                  </p>
                  <div className={styles.formGroup} style={{ marginBottom: '16px' }}>
                    <label className={styles.formLabel}>Official Email (@smvec.ac.in)</label>
                    <input
                      type="email"
                      className={styles.formInput}
                      value={forgotEmail}
                      onChange={(e) => setForgotEmail(e.target.value)}
                      placeholder={forgotRole === 'HOD' ? 'hod.it@smvec.ac.in' : 'staff@smvec.ac.in'}
                      required
                    />
                  </div>
                  <button
                    type="submit"
                    disabled={forgotLoading}
                    className={styles.authSubmitBtn}
                    style={{ width: '100%' }}
                  >
                    {forgotLoading ? 'Dispatching via Resend...' : 'Send Verification Code →'}
                  </button>
                </form>
              )}

              {/* STEP 2: Enter 6-digit OTP */}
              {forgotStep === 2 && (
                <form onSubmit={handleVerifyForgotOtp}>
                  <div style={{ background: '#eff6ff', border: '1px solid #bfdbfe', borderRadius: '6px', padding: '10px', marginBottom: '14px', fontSize: '0.8rem', color: '#1e40af' }}>
                    ✓ Code dispatched via Resend to <strong>{forgotEmail}</strong>.
                  </div>
                  <div className={styles.formGroup} style={{ marginBottom: '16px' }}>
                    <label className={styles.formLabel}>Enter 6-Digit Code</label>
                    <input
                      type="text"
                      className={styles.formInput}
                      value={forgotOtp}
                      onChange={(e) => setForgotOtp(e.target.value)}
                      placeholder="e.g. 849201"
                      maxLength={6}
                      style={{ letterSpacing: '4px', textAlign: 'center', fontSize: '1.2rem', fontWeight: '800' }}
                      required
                    />
                  </div>
                  <button
                    type="submit"
                    disabled={forgotLoading}
                    className={styles.authSubmitBtn}
                    style={{ width: '100%' }}
                  >
                    {forgotLoading ? 'Verifying...' : 'Verify Code →'}
                  </button>
                </form>
              )}

              {/* STEP 3: Verification Successful */}
              {forgotStep === 3 && (
                <div style={{ textAlign: 'center', padding: '10px 0' }}>
                  <div style={{ fontSize: '2rem', marginBottom: '8px' }}>✅</div>
                  <h4 style={{ color: '#065f46', fontSize: '1.05rem', margin: '0 0 8px' }}>Identity Verified</h4>
                  <p style={{ fontSize: '0.85rem', color: '#4b5563', marginBottom: '16px' }}>
                    Your {forgotRole === 'HOD' ? 'HOD' : 'Staff'} identity has been authenticated via Resend. You may now proceed directly to your institutional portal.
                  </p>
                  <button
                    type="button"
                    onClick={() => {
                      setUser({
                        name: forgotRole === 'HOD' ? 'Dr. P. Sivakumar (HOD/IT)' : 'Class Advisor (IT-III-A)',
                        email: forgotEmail,
                        role: forgotRole,
                        department: 'Information Technology',
                        year: 3,
                        section: 'A',
                      });
                      setShowForgotModal(false);
                    }}
                    className={styles.authSubmitBtn}
                    style={{ width: '100%' }}
                  >
                    Proceed to Dashboard →
                  </button>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    );
  }

  // -------------------------------------------------------------
  // RENDER: AUTHENTICATED DASHBOARDS
  // -------------------------------------------------------------
  const userRequests = requests.filter(
    (r) => r.rollNumber === user.rollNumber || r.studentEmail === user.email
  );
  const classRequests = requests.filter((r) => r.year === 3 && r.section === 'A');
  const forwardedToHod = requests.filter((r) => r.status === 'APPROVED_BY_ADVISOR');
  const approvedRequests = requests.filter((r) => r.status === 'APPROVED');

  return (
    <div className={styles.appContainer}>
      {/* Top Navbar */}
      <header className={styles.topNav}>
        <div className={styles.topNavInner}>
          <Link href="/" className={styles.brandGroup}>
            <img src="/college_logo.png" alt="SMVEC Logo" className={styles.brandLogo} />
            <div className={styles.brandInfo}>
              <span className={styles.brandTitle}>SMVEC ON-DUTY SYSTEM</span>
              <span className={styles.brandSubtitle}>
                {user.role === 'STUDENT' && '🎓 Student Portal'}
                {user.role === 'ADVISOR' && '👩‍🏫 Class Advisor Approval Portal'}
                {user.role === 'HOD' && '👨‍💼 HOD Departmental Portal'}
              </span>
            </div>
          </Link>

          <div className={styles.navActions}>
            <span
              className={`${styles.roleBadge} ${
                user.role === 'STUDENT'
                  ? styles.roleBadgeStudent
                  : user.role === 'ADVISOR'
                  ? styles.roleBadgeAdvisor
                  : styles.roleBadgeHod
              }`}
            >
              ● {user.name} ({user.role === 'STUDENT' ? user.rollNumber : user.role})
            </span>

            {/* Sign Out Button */}
            <button
              onClick={() => {
                setUser(null);
                if (clerkSignedIn && clerk?.signOut) {
                  clerk.signOut();
                }
              }}
              style={{
                padding: '6px 12px',
                fontSize: '0.76rem',
                fontWeight: '600',
                background: '#fee2e2',
                color: '#dc2626',
                border: '1px solid #fecaca',
                borderRadius: '6px',
                cursor: 'pointer',
              }}
            >
              Sign Out
            </button>
          </div>
        </div>
      </header>

      {/* Main Container */}
      <main className={styles.mainLayout}>
        {/* ========================================================= */}
        {/* 1. STUDENT VIEW */}
        {/* ========================================================= */}
        {user.role === 'STUDENT' && (
          <div>
            <div className={styles.portalBanner}>
              <div>
                <h2 className={styles.bannerTitle}>Student On-Duty Portal</h2>
                <p className={styles.bannerSub}>
                  {user.name} · Roll: <strong>{user.rollNumber}</strong> · Year {user.year} - Section {user.section} · Dept of {user.department}
                </p>
              </div>
              <button
                className={styles.bannerActionBtn}
                onClick={() => {
                  setFormError('');
                  setShowNewODModal(true);
                }}
                id="btn-new-od"
              >
                + Submit New OD Application
              </button>
            </div>

            {/* Applications List */}
            <div className={styles.cardSection}>
              <h3 className={styles.sectionHeading}>My On-Duty Submissions</h3>

              {userRequests.length === 0 ? (
                <div style={{ textAlign: 'center', padding: '40px 20px', background: '#ffffff', borderRadius: '12px', border: '1px solid #e5e7eb' }}>
                  <div style={{ fontSize: '2.5rem', marginBottom: '10px' }}>📋</div>
                  <h4 style={{ fontSize: '1.1rem', fontWeight: '700', color: '#1e293b', marginBottom: '6px' }}>
                    No OD Requests Submitted Yet
                  </h4>
                  <p style={{ fontSize: '0.85rem', color: '#64748b', maxWidth: '400px', margin: '0 auto 16px' }}>
                    Apply for On-Duty leave for technical hackathons, symposiums, internships, or college representations.
                  </p>
                  <button
                    onClick={() => {
                      setFormError('');
                      setShowNewODModal(true);
                    }}
                    style={{
                      padding: '10px 22px',
                      background: '#3350b0',
                      color: '#ffffff',
                      border: 'none',
                      borderRadius: '8px',
                      fontWeight: '700',
                      fontSize: '0.85rem',
                      cursor: 'pointer',
                    }}
                  >
                    + Submit OD Application
                  </button>
                </div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                  {userRequests.map((req) => (
                    <div key={req.id} className={styles.requestCard}>
                      <div className={styles.requestCardHeader}>
                        <div>
                          <div style={{ display: 'flex', gap: '8px', alignItems: 'center', marginBottom: '4px' }}>
                            <span
                              style={{
                                background: req.submissionType === 'TEAM' ? '#fef3c7' : '#f3f4f6',
                                color: req.submissionType === 'TEAM' ? '#b45309' : '#4b5563',
                                padding: '3px 8px',
                                borderRadius: '6px',
                                fontSize: '0.72rem',
                                fontWeight: '700',
                              }}
                            >
                              {req.submissionType}
                            </span>
                            <span style={{ fontSize: '0.8rem', color: '#9ca3af', fontWeight: '600' }}>
                              #{req.id}
                            </span>
                          </div>
                          <h4 style={{ fontSize: '1.15rem', fontWeight: '800', color: '#1e293b', marginBottom: '4px' }}>
                            {req.eventName}
                          </h4>
                          <div style={{ fontSize: '0.85rem', color: '#6b7280', display: 'flex', gap: '12px' }}>
                            <span>📅 Date: <strong>{req.eventDate}</strong> ({req.eventDay})</span>
                            <span>📎 Document: <em>{req.attachmentName}</em></span>
                          </div>
                        </div>

                        {/* Status Badge */}
                        <div>
                          {req.status === 'APPROVED' && (
                            <span className={`${styles.statusBadge} ${styles.statusApproved}`}>
                              ✓ Fully Sanctioned by HOD
                            </span>
                          )}
                          {req.status === 'APPROVED_BY_ADVISOR' && (
                            <span className={`${styles.statusBadge} ${styles.statusForwarded}`}>
                              ✓ Approved by Class Advisor (Awaiting HOD)
                            </span>
                          )}
                          {req.status === 'PENDING_ADVISOR' && (
                            <span className={`${styles.statusBadge} ${styles.statusPending}`}>
                              ⏳ Waiting for Class Advisor Approval
                            </span>
                          )}
                          {(req.status === 'REJECTED_ADVISOR' || req.status === 'REJECTED_HOD') && (
                            <span className={`${styles.statusBadge} ${styles.statusRejected}`}>
                              ✕ Rejected ({req.status === 'REJECTED_ADVISOR' ? 'by Advisor' : 'by HOD'})
                            </span>
                          )}
                        </div>
                      </div>

                      {/* 4-Step Interactive Progress Stepper */}
                      <div className={styles.stepperTrack}>
                        <div className={styles.stepItem}>
                          <div className={`${styles.stepCircle} ${styles.stepCircleDone}`}>✓</div>
                          <span className={styles.stepLabel}>1. Submitted</span>
                        </div>
                        <div className={`${styles.stepDivider} ${req.status !== 'PENDING_ADVISOR' ? styles.stepDividerDone : ''}`} />
                        <div className={styles.stepItem}>
                          <div
                            className={`${styles.stepCircle} ${
                              req.status === 'REJECTED_ADVISOR'
                                ? styles.stepCircleRejected
                                : req.status === 'APPROVED_BY_ADVISOR' || req.status === 'APPROVED'
                                ? styles.stepCircleDone
                                : styles.stepCircleActive
                            }`}
                          >
                            {req.status === 'REJECTED_ADVISOR' ? '✕' : req.status === 'APPROVED_BY_ADVISOR' || req.status === 'APPROVED' ? '✓' : '2'}
                          </div>
                          <span className={styles.stepLabel}>
                            {req.status === 'APPROVED_BY_ADVISOR' || req.status === 'APPROVED'
                              ? '2. Advisor Approved ✓'
                              : '2. Advisor Approval'}
                          </span>
                        </div>
                        <div className={`${styles.stepDivider} ${req.status === 'APPROVED' ? styles.stepDividerDone : ''}`} />
                        <div className={styles.stepItem}>
                          <div
                            className={`${styles.stepCircle} ${
                              req.status === 'REJECTED_HOD'
                                ? styles.stepCircleRejected
                                : req.status === 'APPROVED'
                                ? styles.stepCircleDone
                                : req.status === 'APPROVED_BY_ADVISOR'
                                ? styles.stepCircleActive
                                : styles.stepCirclePending
                            }`}
                          >
                            {req.status === 'REJECTED_HOD' ? '✕' : req.status === 'APPROVED' ? '✓' : '3'}
                          </div>
                          <span className={styles.stepLabel}>
                            {req.status === 'APPROVED' ? '3. HOD Sanctioned ✓' : '3. HOD Decision'}
                          </span>
                        </div>
                        <div className={`${styles.stepDivider} ${req.status === 'APPROVED' ? styles.stepDividerDone : ''}`} />
                        <div className={styles.stepItem}>
                          <div
                            className={`${styles.stepCircle} ${
                              req.status === 'APPROVED' ? styles.stepCircleDone : styles.stepCirclePending
                            }`}
                          >
                            {req.status === 'APPROVED' ? '🎓' : '4'}
                          </div>
                          <span className={styles.stepLabel}>4. OD Sanction Valid</span>
                        </div>
                      </div>

                      <p style={{ fontSize: '0.88rem', color: '#4b5563', lineHeight: '1.5', margin: '8px 0' }}>
                        {req.description}
                      </p>

                      {/* Remarks from Advisor / HOD */}
                      <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap', marginTop: '12px' }}>
                        {req.advisorRemarks && (
                          <div
                            style={{
                              flex: 1,
                              minWidth: '240px',
                              background: '#eff6ff',
                              border: '1px solid #bfdbfe',
                              padding: '10px 14px',
                              borderRadius: '8px',
                              fontSize: '0.8rem',
                            }}
                          >
                            <span style={{ fontWeight: '700', color: '#1e40af' }}>
                              👩‍🏫 Class Advisor Note ({req.advisorName}):
                            </span>
                            <div style={{ color: '#1e3a8a', marginTop: '2px' }}>{req.advisorRemarks}</div>
                          </div>
                        )}
                        {req.hodRemarks && (
                          <div
                            style={{
                              flex: 1,
                              minWidth: '240px',
                              background: '#ecfdf5',
                              border: '1px solid #a7f3d0',
                              padding: '10px 14px',
                              borderRadius: '8px',
                              fontSize: '0.8rem',
                            }}
                          >
                            <span style={{ fontWeight: '700', color: '#065f46' }}>
                              👨‍💼 Official HOD Sanction Seal ({req.hodName}):
                            </span>
                            <div style={{ color: '#047857', marginTop: '2px' }}>{req.hodRemarks}</div>
                          </div>
                        )}
                      </div>

                      {/* Result Submission Section */}
                      {req.status === 'APPROVED' && (
                        <div
                          style={{
                            marginTop: '14px',
                            paddingTop: '12px',
                            borderTop: '1px solid #e5e7eb',
                            display: 'flex',
                            justifyContent: 'space-between',
                            alignItems: 'center',
                            flexWrap: 'wrap',
                            gap: '10px',
                          }}
                        >
                          {req.resultStatus !== 'PENDING' ? (
                            <div style={{ fontSize: '0.85rem' }}>
                              🏆 <strong>Result Recorded:</strong> {req.resultStatus} · <em>{req.resultProjectName}</em>
                            </div>
                          ) : (
                            <div style={{ fontSize: '0.85rem', color: '#6b7280' }}>
                              Event finished? Record your achievements & upload certificates.
                            </div>
                          )}

                          {req.resultStatus === 'PENDING' && (
                            <button
                              style={{
                                padding: '8px 16px',
                                background: '#d4a429',
                                color: '#ffffff',
                                border: 'none',
                                borderRadius: '8px',
                                fontSize: '0.8rem',
                                fontWeight: '700',
                                cursor: 'pointer',
                              }}
                              onClick={() => {
                                setShowResultModal(req);
                                setResultData({ status: 'WON', projectName: req.eventName, description: '' });
                              }}
                            >
                              🏆 Submit Event Results
                            </button>
                          )}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}

        {/* ========================================================= */}
        {/* 2. CLASS ADVISOR VIEW */}
        {/* ========================================================= */}
        {user.role === 'ADVISOR' && (
          <div>
            <div className={styles.portalBanner}>
              <div>
                <h2 className={styles.bannerTitle}>Class Advisor Approval Authority</h2>
                <p className={styles.bannerSub}>
                  {user.name} · Dept of {user.department} · In-Charge: <strong>Year {user.year} - Section {user.section}</strong>
                </p>
              </div>
              <div style={{ fontSize: '0.85rem', background: 'rgba(255,255,255,0.2)', padding: '8px 16px', borderRadius: '8px' }}>
                Pending Class Requests: <strong>{classRequests.filter((r) => r.status === 'PENDING_ADVISOR').length}</strong>
              </div>
            </div>

            {/* Instruction Callout */}
            <div style={{ background: '#fffbeb', border: '1px solid #fde68a', borderRadius: '12px', padding: '12px 18px', marginBottom: '20px', display: 'flex', alignItems: 'center', gap: '12px', fontSize: '0.85rem', color: '#92400e' }}>
              <span style={{ fontSize: '1.2rem' }}>⚡</span>
              <div>
                <strong>Class Advisor Approval Gate:</strong> You must click <strong>"✓ Approve OD Request"</strong> on a student submission to verify attendance and permit it to move to HOD for final sanction. Without your approval, the student cannot receive On-Duty status.
              </div>
            </div>

            {/* Submissions List */}
            <div className={styles.cardSection}>
              <h3 className={styles.sectionHeading} style={{ marginBottom: '16px' }}>
                Class Submissions Queue
              </h3>

              {classRequests.length === 0 ? (
                <div style={{ textAlign: 'center', padding: '40px 20px', background: '#ffffff', borderRadius: '12px', border: '1px solid #e5e7eb' }}>
                  <div style={{ fontSize: '2.5rem', marginBottom: '10px' }}>📭</div>
                  <h4 style={{ fontSize: '1.1rem', fontWeight: '700', color: '#1e293b', marginBottom: '6px' }}>
                    No OD Requests in Queue
                  </h4>
                  <p style={{ fontSize: '0.85rem', color: '#64748b' }}>
                    When students from your class submit On-Duty applications, they will appear here for your verification.
                  </p>
                </div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
                  {classRequests.map((req) => (
                    <div
                      key={req.id}
                      style={{
                        padding: '18px',
                        border: req.status === 'PENDING_ADVISOR' ? '2px solid #f59e0b' : '1px solid #e5e7eb',
                        borderRadius: '12px',
                        background: '#ffffff',
                        boxShadow: req.status === 'PENDING_ADVISOR' ? '0 4px 12px rgba(245,158,11,0.08)' : 'none',
                      }}
                    >
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: '10px' }}>
                        <div>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                            <span style={{ fontWeight: '800', fontSize: '1.05rem', color: '#1e293b' }}>
                              {req.studentName}
                            </span>
                            <span style={{ fontSize: '0.82rem', color: '#6b7280' }}>
                              (Roll: {req.rollNumber})
                            </span>
                            <span
                              style={{
                                background: '#eff6ff',
                                color: '#1d4ed8',
                                fontSize: '0.72rem',
                                padding: '2px 6px',
                                borderRadius: '4px',
                                fontWeight: '700',
                              }}
                            >
                              {req.submissionType}
                            </span>
                          </div>
                          <div style={{ fontSize: '0.98rem', fontWeight: '700', color: '#3350b0', margin: '4px 0' }}>
                            {req.eventName} ({req.eventType})
                          </div>
                          <div style={{ fontSize: '0.82rem', color: '#6b7280' }}>
                            📅 Date: {req.eventDate} ({req.eventDay}) · 📎 Document: {req.attachmentName}
                          </div>
                        </div>

                        <div>
                          {req.status === 'PENDING_ADVISOR' ? (
                            <span className={`${styles.statusBadge} ${styles.statusPending}`}>
                              ⏳ Action Required: Click Approve
                            </span>
                          ) : req.status === 'APPROVED_BY_ADVISOR' ? (
                            <span className={`${styles.statusBadge} ${styles.statusForwarded}`}>
                              ✓ Approved by You (At HOD)
                            </span>
                          ) : req.status === 'APPROVED' ? (
                            <span className={`${styles.statusBadge} ${styles.statusApproved}`}>
                              HOD Approved ✓
                            </span>
                          ) : (
                            <span className={`${styles.statusBadge} ${styles.statusRejected}`}>
                              Rejected
                            </span>
                          )}
                        </div>
                      </div>

                      <p style={{ fontSize: '0.85rem', color: '#4b5563', margin: '10px 0', background: '#f9fafb', padding: '10px', borderRadius: '8px' }}>
                        {req.description}
                      </p>

                      {/* Action buttons */}
                      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px', marginTop: '10px' }}>
                        {req.status === 'PENDING_ADVISOR' ? (
                          <>
                            <button
                              style={{
                                padding: '8px 16px',
                                background: '#fee2e2',
                                color: '#dc2626',
                                border: '1px solid #fecaca',
                                borderRadius: '8px',
                                fontSize: '0.82rem',
                                fontWeight: '700',
                                cursor: 'pointer',
                              }}
                              onClick={() => {
                                setShowReviewModal(req);
                                setReviewRemarks('');
                              }}
                            >
                              ✕ Reject with Feedback
                            </button>
                            <button
                              style={{
                                padding: '10px 22px',
                                background: '#059669',
                                color: '#ffffff',
                                border: 'none',
                                borderRadius: '8px',
                                fontSize: '0.85rem',
                                fontWeight: '700',
                                cursor: 'pointer',
                                boxShadow: '0 2px 8px rgba(5,150,105,0.3)',
                              }}
                              onClick={() => {
                                setShowReviewModal(req);
                                setReviewRemarks('Verified attendance and academic standing. Approved by Class Advisor.');
                              }}
                              id="btn-advisor-approve"
                            >
                              ✓ Approve OD Request →
                            </button>
                          </>
                        ) : (
                          <div style={{ fontSize: '0.8rem', color: '#065f46', background: '#f0fdf4', padding: '6px 12px', borderRadius: '6px' }}>
                            ✓ <strong>Advisor Endorsement:</strong> "{req.advisorRemarks}"
                          </div>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}

        {/* ========================================================= */}
        {/* 3. HOD VIEW */}
        {/* ========================================================= */}
        {user.role === 'HOD' && (
          <div>
            <div className={styles.portalBanner}>
              <div>
                <h2 className={styles.bannerTitle}>HOD Departmental Executive Portal</h2>
                <p className={styles.bannerSub}>
                  {user.name} · Head of Department, {user.department} · Sri Manakula Vinayagar Eng. College
                </p>
              </div>
              <button
                className={styles.bannerActionBtn}
                onClick={handleExportCSV}
                id="btn-export-report"
              >
                📥 Export Department OD Report (CSV)
              </button>
            </div>

            {/* HOD Tabs */}
            <div style={{ display: 'flex', gap: '8px', marginBottom: '20px' }}>
              <button
                className={`${styles.roleTab} ${hodTab === 'PENDING' ? styles.roleTabActive : ''}`}
                style={{ flex: 'none', padding: '8px 18px', border: '1px solid #e5e7eb' }}
                onClick={() => setHodTab('PENDING')}
              >
                Advisor-Approved Awaiting Sanction ({forwardedToHod.length})
              </button>
              <button
                className={`${styles.roleTab} ${hodTab === 'APPROVED' ? styles.roleTabActive : ''}`}
                style={{ flex: 'none', padding: '8px 18px', border: '1px solid #e5e7eb' }}
                onClick={() => setHodTab('APPROVED')}
              >
                Sanctioned Archive ({approvedRequests.length})
              </button>
              <button
                className={`${styles.roleTab} ${hodTab === 'AUDIT' ? styles.roleTabActive : ''}`}
                style={{ flex: 'none', padding: '8px 18px', border: '1px solid #e5e7eb' }}
                onClick={() => setHodTab('AUDIT')}
              >
                Live Audit Trail ({auditLogs.length})
              </button>
            </div>

            {/* TAB 1: PENDING HOD SANCTION */}
            {hodTab === 'PENDING' && (
              <div className={styles.cardSection}>
                <h3 className={styles.sectionHeading} style={{ marginBottom: '16px' }}>
                  Requests Endorsed by Class Advisors (Awaiting Final HOD Sanction)
                </h3>

                {forwardedToHod.length === 0 ? (
                  <div style={{ textAlign: 'center', padding: '40px 20px', background: '#ffffff', borderRadius: '12px', border: '1px solid #e5e7eb' }}>
                    <div style={{ fontSize: '2.5rem', marginBottom: '10px' }}>📭</div>
                    <h4 style={{ fontSize: '1.1rem', fontWeight: '700', color: '#1e293b', marginBottom: '6px' }}>
                      No Requests Awaiting HOD Sanction
                    </h4>
                    <p style={{ fontSize: '0.85rem', color: '#64748b' }}>
                      Only requests that have been verified and approved by Class Advisors will appear here for final sanction.
                    </p>
                  </div>
                ) : (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
                    {forwardedToHod.map((req) => (
                      <div
                        key={req.id}
                        style={{
                          padding: '20px',
                          border: '2px solid #2563eb',
                          borderRadius: '12px',
                          background: '#ffffff',
                          boxShadow: '0 4px 14px rgba(37,99,235,0.08)',
                        }}
                      >
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: '10px', marginBottom: '12px' }}>
                          <div>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                              <span style={{ fontWeight: '800', fontSize: '1.1rem', color: '#1e293b' }}>
                                {req.studentName}
                              </span>
                              <span style={{ fontSize: '0.85rem', color: '#6b7280' }}>
                                (Roll: {req.rollNumber} · Year {req.year}-{req.section})
                              </span>
                            </div>
                            <div style={{ fontSize: '1.05rem', fontWeight: '700', color: '#3350b0', margin: '4px 0' }}>
                              {req.eventName} ({req.eventType})
                            </div>
                            <div style={{ fontSize: '0.82rem', color: '#6b7280' }}>
                              📅 Event Date: {req.eventDate} ({req.eventDay}) · 📎 Document: {req.attachmentName}
                            </div>
                          </div>

                          <span className={`${styles.statusBadge} ${styles.statusForwarded}`}>
                            ⚡ Advisor Endorsed
                          </span>
                        </div>

                        {/* Advisor Recommendation Note */}
                        <div
                          style={{
                            background: '#eff6ff',
                            borderLeft: '4px solid #3b82f6',
                            padding: '10px 14px',
                            borderRadius: '6px',
                            marginBottom: '16px',
                          }}
                        >
                          <div style={{ fontSize: '0.78rem', fontWeight: '700', color: '#1e40af' }}>
                            Class Advisor Official Recommendation ({req.advisorName}):
                          </div>
                          <div style={{ fontSize: '0.82rem', color: '#1e3a8a', marginTop: '2px' }}>
                            "{req.advisorRemarks}"
                          </div>
                        </div>

                        {/* Action Buttons */}
                        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
                          <button
                            style={{
                              padding: '8px 18px',
                              background: '#fee2e2',
                              color: '#dc2626',
                              border: '1px solid #fecaca',
                              borderRadius: '8px',
                              fontSize: '0.85rem',
                              fontWeight: '700',
                              cursor: 'pointer',
                            }}
                            onClick={() => {
                              setShowReviewModal(req);
                              setReviewRemarks('');
                            }}
                          >
                            Reject OD
                          </button>
                          <button
                            style={{
                              padding: '10px 24px',
                              background: '#059669',
                              color: '#ffffff',
                              border: 'none',
                              borderRadius: '8px',
                              fontSize: '0.85rem',
                              fontWeight: '700',
                              cursor: 'pointer',
                              boxShadow: '0 2px 8px rgba(5,150,105,0.3)',
                            }}
                            onClick={() => handleHodApprove(req.id)}
                            id="btn-hod-sanction"
                          >
                            ✓ Officially Sanction OD (Send Confirmation Mail)
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}

            {/* TAB 2: Sanctioned Archive */}
            {hodTab === 'APPROVED' && (
              <div className={styles.cardSection}>
                <h3 className={styles.sectionHeading} style={{ marginBottom: '16px' }}>
                  Officially Sanctioned On-Duty Records
                </h3>

                {approvedRequests.length === 0 ? (
                  <div style={{ textAlign: 'center', padding: '30px', color: '#64748b' }}>
                    No OD applications have received final sanction yet.
                  </div>
                ) : (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                    {approvedRequests.map((req) => (
                      <div
                        key={req.id}
                        style={{
                          padding: '14px 18px',
                          border: '1px solid #a7f3d0',
                          background: '#f0fdf4',
                          borderRadius: '10px',
                          display: 'flex',
                          justifyContent: 'space-between',
                          alignItems: 'center',
                          flexWrap: 'wrap',
                          gap: '10px',
                        }}
                      >
                        <div>
                          <div style={{ fontWeight: '800', color: '#065f46' }}>
                            {req.studentName} ({req.rollNumber}) · {req.eventName}
                          </div>
                          <div style={{ fontSize: '0.8rem', color: '#047857' }}>
                            Sanctioned by {req.hodName} on {req.eventDate} ({req.eventType}) · {req.submissionType}
                          </div>
                          <div style={{ fontSize: '0.75rem', color: '#059669', marginTop: '2px' }}>
                            Vetted by Advisor: {req.advisorName} · Student Email: {req.studentEmail}
                          </div>
                        </div>
                        <span className={`${styles.statusBadge} ${styles.statusApproved}`}>
                          Official OD Valid ✓
                        </span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}

            {/* TAB 3: Audit Trail */}
            {hodTab === 'AUDIT' && (
              <div className={styles.cardSection}>
                <h3 className={styles.sectionHeading} style={{ marginBottom: '16px' }}>
                  Live System Audit Trail & Decision Log
                </h3>

                {auditLogs.length === 0 ? (
                  <div style={{ textAlign: 'center', padding: '30px', color: '#64748b' }}>
                    No audit records logged yet.
                  </div>
                ) : (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                    {auditLogs.map((log) => (
                      <div
                        key={log.id}
                        style={{
                          padding: '12px 16px',
                          border: '1px solid #e5e7eb',
                          borderRadius: '8px',
                          background: '#f9fafb',
                          display: 'flex',
                          alignItems: 'center',
                          gap: '14px',
                        }}
                      >
                        <div
                          style={{
                            width: '10px',
                            height: '10px',
                            borderRadius: '50%',
                            background:
                              log.action === 'APPROVED' || log.action === 'SANCTIONED_BY_HOD'
                                ? '#059669'
                                : log.action === 'APPROVED_BY_ADVISOR'
                                ? '#2563eb'
                                : log.action.includes('REJECTED')
                                ? '#dc2626'
                                : '#3350b0',
                          }}
                        />
                        <div style={{ flex: 1 }}>
                          <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <span style={{ fontSize: '0.85rem', fontWeight: '700', color: '#1e293b' }}>
                              [{log.role}] {log.actor} | {log.action.replace(/_/g, ' ')}
                            </span>
                            <span style={{ fontSize: '0.75rem', color: '#9ca3af' }}>{log.time}</span>
                          </div>
                          <div style={{ fontSize: '0.8rem', color: '#4b5563', marginTop: '2px' }}>
                            {log.details}
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}
          </div>
        )}
      </main>

      {/* ========================================================= */}
      {/* MODAL: CREATE NEW OD REQUEST (STUDENT - NO WATERMARK) */}
      {/* ========================================================= */}
      {showNewODModal && (
        <div className={styles.modalBackdrop}>
          <div className={styles.modalBox} style={{ maxWidth: '520px' }}>
            <div className={styles.modalHeader}>
              <h3 className={styles.modalTitle}>Submit On-Duty Application</h3>
              <button className={styles.closeModalBtn} onClick={() => setShowNewODModal(false)}>
                ✕
              </button>
            </div>

            {formError && (
              <div style={{ background: '#fef2f2', border: '1px solid #fecaca', borderRadius: '6px', padding: '10px', marginBottom: '14px', color: '#b91c1c', fontSize: '0.82rem' }}>
                {formError}
              </div>
            )}

            <form onSubmit={handleCreateOD}>
              {/* Participation Type */}
              <div className={styles.formGroup} style={{ marginBottom: '14px' }}>
                <label className={styles.formLabel}>Participation Type</label>
                <div style={{ display: 'flex', gap: '10px' }}>
                  <button
                    type="button"
                    className={`${styles.roleTab} ${formData.submissionType === 'SOLO' ? styles.roleTabActive : ''}`}
                    style={{ border: '1px solid #d1d5db' }}
                    onClick={() => setFormData({ ...formData, submissionType: 'SOLO' })}
                  >
                    👤 Solo
                  </button>
                  <button
                    type="button"
                    className={`${styles.roleTab} ${formData.submissionType === 'TEAM' ? styles.roleTabActive : ''}`}
                    style={{ border: '1px solid #d1d5db' }}
                    onClick={() => setFormData({ ...formData, submissionType: 'TEAM' })}
                  >
                    👥 Team
                  </button>
                </div>
              </div>

              {/* Event Category */}
              <div className={styles.formGroup} style={{ marginBottom: '14px' }}>
                <label className={styles.formLabel}>Event Category</label>
                <select
                  className={styles.formInput}
                  value={formData.eventType}
                  onChange={(e) => setFormData({ ...formData, eventType: e.target.value })}
                >
                  <option value="Hackathon">Hackathon</option>
                  <option value="Internship">Internship</option>
                  <option value="Paper Presentation">Paper Presentation</option>
                  <option value="Workshop">Technical Workshop</option>
                  <option value="Symposium">College Symposium</option>
                  <option value="Sports">Sports / Cultural</option>
                  <option value="Other">Other</option>
                </select>
              </div>

              {/* Event Name - CLEAN INPUT NO WATERMARK */}
              <div className={styles.formGroup} style={{ marginBottom: '14px' }}>
                <label className={styles.formLabel}>Official Event Name</label>
                <input
                  type="text"
                  className={styles.formInput}
                  value={formData.eventName}
                  onChange={(e) => setFormData({ ...formData, eventName: e.target.value })}
                  placeholder="Enter full name of the event / competition"
                  required
                />
              </div>

              {/* Event Date & Day */}
              <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: '12px', marginBottom: '14px' }}>
                <div className={styles.formGroup}>
                  <label className={styles.formLabel}>Event Date</label>
                  <input
                    type="date"
                    className={styles.formInput}
                    value={formData.eventDate}
                    onChange={handleDateChange}
                    required
                  />
                </div>
                <div className={styles.formGroup}>
                  <label className={styles.formLabel}>Day</label>
                  <input
                    type="text"
                    className={styles.formInput}
                    value={formData.eventDay}
                    readOnly
                    style={{ background: '#f3f4f6', color: '#4b5563' }}
                    placeholder="Auto-calculated"
                  />
                </div>
              </div>

              {/* Description - CLEAN INPUT NO WATERMARK */}
              <div className={styles.formGroup} style={{ marginBottom: '14px' }}>
                <label className={styles.formLabel}>Detailed Purpose / Venue Details</label>
                <textarea
                  className={styles.formInput}
                  rows={3}
                  value={formData.description}
                  onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                  placeholder="Provide event details, venue address, and reporting time"
                  required
                />
              </div>

              {/* REAL FILE ATTACHMENT UPLOAD (WATERMARK COMPLETELY REMOVED) */}
              <div className={styles.formGroup} style={{ marginBottom: '20px' }}>
                <label className={styles.formLabel}>Event Document / Proof Attachment (PDF, JPG, PNG)</label>
                <input
                  type="file"
                  accept=".pdf,.png,.jpg,.jpeg"
                  className={styles.formInput}
                  onChange={(e) => {
                    const f = e.target.files?.[0];
                    if (f) setSelectedFile(f);
                  }}
                  id="file-upload-input"
                />
                {selectedFile ? (
                  <div style={{ marginTop: '8px', fontSize: '0.82rem', color: '#059669', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <span>📎 Selected: <strong>{selectedFile.name}</strong> ({(selectedFile.size / 1024).toFixed(1)} KB)</span>
                    <button
                      type="button"
                      onClick={() => {
                        setSelectedFile(null);
                        const inp = document.getElementById('file-upload-input');
                        if (inp) inp.value = '';
                      }}
                      style={{ background: 'transparent', border: 'none', color: '#dc2626', cursor: 'pointer', fontSize: '0.8rem' }}
                    >
                      ✕ Remove
                    </button>
                  </div>
                ) : (
                  <span style={{ fontSize: '0.74rem', color: '#64748b', marginTop: '4px', display: 'block' }}>
                    Attach your invitation letter, registration receipt, or brochure.
                  </span>
                )}
              </div>

              <button type="submit" className={styles.authSubmitBtn} style={{ width: '100%' }}>
                Submit to Class Advisor for Approval →
              </button>
            </form>
          </div>
        </div>
      )}

      {/* ========================================================= */}
      {/* MODAL: ADVISOR / HOD REVIEW & APPROVAL MODAL */}
      {/* ========================================================= */}
      {showReviewModal && (
        <div className={styles.modalBackdrop}>
          <div className={styles.modalBox}>
            <div className={styles.modalHeader}>
              <h3 className={styles.modalTitle}>
                {user.role === 'ADVISOR' ? 'Class Advisor Review & Approval' : 'HOD Final Sanction Review'} (#{showReviewModal.id})
              </h3>
              <button className={styles.closeModalBtn} onClick={() => setShowReviewModal(null)}>
                ✕
              </button>
            </div>

            <div>
              <p><strong>Student:</strong> {showReviewModal.studentName} ({showReviewModal.rollNumber})</p>
              <p><strong>Class:</strong> Year {showReviewModal.year} - Section {showReviewModal.section} · {showReviewModal.department}</p>
              <p><strong>Event:</strong> {showReviewModal.eventName} ({showReviewModal.eventType})</p>
              <p><strong>Date:</strong> {showReviewModal.eventDate} ({showReviewModal.eventDay})</p>
              <p><strong>Document:</strong> {showReviewModal.attachmentName}</p>
              <p style={{ marginTop: '8px', color: '#4b5563' }}><strong>Description:</strong> {showReviewModal.description}</p>

              {showReviewModal.advisorRemarks && (
                <div style={{ background: '#eff6ff', padding: '10px', borderRadius: '8px', margin: '12px 0' }}>
                  <strong>Advisor Approval Note:</strong> "{showReviewModal.advisorRemarks}"
                </div>
              )}

              <div style={{ marginTop: '16px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
                <label className={styles.formLabel}>
                  {user.role === 'ADVISOR' ? 'Class Advisor Remarks:' : 'Official HOD Sanction Remarks:'}
                </label>
                <textarea
                  className={styles.formInput}
                  rows={3}
                  value={reviewRemarks}
                  onChange={(e) => setReviewRemarks(e.target.value)}
                  placeholder={
                    user.role === 'ADVISOR'
                      ? 'e.g. Verified attendance criteria. Recommended for college representation.'
                      : 'e.g. Approved with full attendance compensation.'
                  }
                />
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px', marginTop: '20px' }}>
                <button
                  style={{
                    padding: '10px 18px',
                    background: '#fee2e2',
                    color: '#dc2626',
                    border: '1px solid #fecaca',
                    borderRadius: '8px',
                    fontWeight: '700',
                    cursor: 'pointer',
                  }}
                  onClick={() => {
                    if (user.role === 'ADVISOR') handleAdvisorReject(showReviewModal.id);
                    if (user.role === 'HOD') handleHodReject(showReviewModal.id);
                  }}
                >
                  Reject Request
                </button>

                {user.role === 'ADVISOR' ? (
                  <button
                    style={{
                      padding: '10px 22px',
                      background: '#059669',
                      color: '#ffffff',
                      border: 'none',
                      borderRadius: '8px',
                      fontWeight: '700',
                      cursor: 'pointer',
                      boxShadow: '0 2px 8px rgba(5,150,105,0.3)',
                    }}
                    onClick={() => handleAdvisorApprove(showReviewModal.id)}
                  >
                    ✓ Approve & Forward to HOD →
                  </button>
                ) : (
                  <button
                    style={{
                      padding: '10px 22px',
                      background: '#059669',
                      color: '#ffffff',
                      border: 'none',
                      borderRadius: '8px',
                      fontWeight: '700',
                      cursor: 'pointer',
                      boxShadow: '0 2px 8px rgba(5,150,105,0.3)',
                    }}
                    onClick={() => handleHodApprove(showReviewModal.id)}
                  >
                    ✓ Officially Sanction OD (Send Mail)
                  </button>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ========================================================= */}
      {/* MODAL: POST-EVENT RESULT SUBMISSION */}
      {/* ========================================================= */}
      {showResultModal && (
        <div className={styles.modalBackdrop}>
          <div className={styles.modalBox}>
            <div className={styles.modalHeader}>
              <h3 className={styles.modalTitle}>Submit Post-Event Achievement</h3>
              <button className={styles.closeModalBtn} onClick={() => setShowResultModal(null)}>
                ✕
              </button>
            </div>

            <form onSubmit={handleSaveResult}>
              <p style={{ marginBottom: '14px', fontSize: '0.9rem' }}>
                Event: <strong>{showResultModal.eventName}</strong>
              </p>

              <div className={styles.formGroup} style={{ marginBottom: '14px' }}>
                <label className={styles.formLabel}>Achievement Result</label>
                <select
                  className={styles.formInput}
                  value={resultData.status}
                  onChange={(e) => setResultData({ ...resultData, status: e.target.value })}
                >
                  <option value="WON">🏆 Won 1st / 2nd / 3rd Prize</option>
                  <option value="SPECIAL_AWARD">🎖️ Special Jury Award / Cash Prize</option>
                  <option value="PARTICIPATION">📜 Successful Participation</option>
                </select>
              </div>

              <div className={styles.formGroup} style={{ marginBottom: '14px' }}>
                <label className={styles.formLabel}>Project / Paper Title</label>
                <input
                  type="text"
                  className={styles.formInput}
                  value={resultData.projectName}
                  onChange={(e) => setResultData({ ...resultData, projectName: e.target.value })}
                  placeholder="Enter project or presentation title"
                  required
                />
              </div>

              {/* REAL CERTIFICATE UPLOAD NO WATERMARK */}
              <div className={styles.formGroup} style={{ marginBottom: '20px' }}>
                <label className={styles.formLabel}>Certificate / Proof Attachment</label>
                <input
                  type="file"
                  accept=".pdf,.png,.jpg,.jpeg"
                  className={styles.formInput}
                  onChange={(e) => {
                    const f = e.target.files?.[0];
                    if (f) setResultFile(f);
                  }}
                />
                {resultFile && (
                  <span style={{ fontSize: '0.8rem', color: '#059669', display: 'block', marginTop: '4px' }}>
                    📎 {resultFile.name} ({(resultFile.size / 1024).toFixed(1)} KB)
                  </span>
                )}
              </div>

              <button type="submit" className={styles.authSubmitBtn} style={{ width: '100%' }}>
                Save Achievement to College Records →
              </button>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
