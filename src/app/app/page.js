'use client';

import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import styles from './app.module.css';

// Initial Mock Seed Data matching the SMVEC Reference Architecture
const INITIAL_REQUESTS = [
  {
    id: 'OD-2026-001',
    studentName: 'Aravindhan S',
    rollNumber: '21IT101',
    department: 'Information Technology',
    year: 3,
    section: 'A',
    submissionType: 'TEAM',
    teamMembers: ['Aravindhan S (21IT101)', 'Priya K (21IT102)', 'Rahul M (21IT103)'],
    eventType: 'Hackathon',
    eventName: 'Smart India Hackathon 2026 (Grand Finale)',
    eventDate: '2026-09-22',
    eventDay: 'Tuesday',
    description: 'Selected for National Grand Finale at Bengaluru Nodal Center. Need 3 days On-Duty sanction for travel and contest participation.',
    status: 'APPROVED', // 'PENDING_ADVISOR', 'FORWARDED_HOD', 'APPROVED', 'REJECTED_ADVISOR', 'REJECTED_HOD'
    attachmentName: 'SIH_Shortlist_Letter.pdf',
    advisorRemarks: 'Verified student academic record (CGPA > 8.5) and attendance (> 85%). Recommended for college representation.',
    advisorName: 'Dr. K. Senthil',
    advisorTimestamp: '2026-09-15 11:30 AM',
    hodRemarks: 'Sanctioned with travel allowance and full attendance compensation. All the best to the team!',
    hodName: 'Dr. P. Sivakumar',
    hodTimestamp: '2026-09-16 03:45 PM',
    resultStatus: 'WON',
    resultProjectName: 'AI Autonomous Drone for Crop Health Monitoring',
    resultCertificate: 'SIH_First_Prize_Cert.pdf',
    createdAt: '2026-09-14 10:15 AM',
  },
  {
    id: 'OD-2026-002',
    studentName: 'Karthik R',
    rollNumber: '21IT115',
    department: 'Information Technology',
    year: 3,
    section: 'A',
    submissionType: 'SOLO',
    teamMembers: [],
    eventType: 'Internship',
    eventName: 'TCS iON Industrial Cloud Immersion',
    eventDate: '2026-09-25',
    eventDay: 'Friday',
    description: 'Selected for 2-week hands-on industrial immersion on AWS and DevSecOps at TCS Siruseri campus.',
    status: 'FORWARDED_HOD',
    attachmentName: 'TCS_Selection_Offer.pdf',
    advisorRemarks: 'Offer letter checked with TCS portal. Academic calendar verified. Recommended for HOD sanction.',
    advisorName: 'Dr. K. Senthil',
    advisorTimestamp: '2026-09-16 09:30 AM',
    hodRemarks: null,
    hodName: null,
    hodTimestamp: null,
    resultStatus: 'PENDING',
    createdAt: '2026-09-15 04:20 PM',
  },
  {
    id: 'OD-2026-003',
    studentName: 'Sneha M',
    rollNumber: '21IT142',
    department: 'Information Technology',
    year: 3,
    section: 'A',
    submissionType: 'TEAM',
    teamMembers: ['Sneha M (21IT142)', 'Divya S (21IT143)'],
    eventType: 'Paper Presentation',
    eventName: 'IEEE ICAIoT 2026 International Conference',
    eventDate: '2026-09-30',
    eventDay: 'Wednesday',
    description: 'Oral presentation of research paper on Edge AI for Predictive Agriculture in Pondicherry University.',
    status: 'PENDING_ADVISOR',
    attachmentName: 'IEEE_Acceptance_Proof.pdf',
    advisorRemarks: null,
    advisorName: null,
    advisorTimestamp: null,
    hodRemarks: null,
    hodName: null,
    hodTimestamp: null,
    resultStatus: 'PENDING',
    createdAt: '2026-09-17 01:10 PM',
  },
];

const INITIAL_AUDIT = [
  { id: 'AUD-01', action: 'CREATED', actor: 'Aravindhan S (21IT101)', role: 'STUDENT', time: '14 Sep, 10:15 AM', details: 'Submitted OD request for Smart India Hackathon' },
  { id: 'AUD-02', action: 'FORWARDED', actor: 'Dr. K. Senthil', role: 'ADVISOR', time: '15 Sep, 11:30 AM', details: 'Class Advisor reviewed attendance (>85%) and forwarded to HOD' },
  { id: 'AUD-03', action: 'APPROVED', actor: 'Dr. P. Sivakumar', role: 'HOD', time: '16 Sep, 03:45 PM', details: 'HOD approved final On-Duty sanction with digital signature' },
];

const INITIAL_NOTIFICATIONS = [
  { id: 'N-1', title: 'OD Approved 🎉', text: 'Smart India Hackathon OD has been sanctioned by HOD Dr. P. Sivakumar.', time: 'Yesterday', role: 'STUDENT' },
  { id: 'N-2', title: 'New Submission 📋', text: 'Sneha M (21IT142) submitted an OD request for IEEE ICAIoT 2026.', time: '2 hours ago', role: 'ADVISOR' },
  { id: 'N-3', title: 'Forwarded for Sanction ⚡', text: 'Dr. K. Senthil forwarded TCS Internship request for Karthik R.', time: '1 day ago', role: 'HOD' },
];

export default function AppPortal() {
  // Current Authenticated User State
  const [user, setUser] = useState(null); // { name, email, role: 'STUDENT' | 'ADVISOR' | 'HOD', rollNumber, year, section }
  
  // App State
  const [requests, setRequests] = useState(INITIAL_REQUESTS);
  const [auditLogs, setAuditLogs] = useState(INITIAL_AUDIT);
  const [notifications, setNotifications] = useState(INITIAL_NOTIFICATIONS);
  const [showNotifDrawer, setShowNotifDrawer] = useState(false);

  // Modals
  const [showNewODModal, setShowNewODModal] = useState(false);
  const [showReviewModal, setShowReviewModal] = useState(null); // request to review
  const [showResultModal, setShowResultModal] = useState(null); // request to add result
  const [advisorFilter, setAdvisorFilter] = useState('ALL'); // 'ALL', 'PENDING', 'FORWARDED', 'REJECTED'
  const [hodTab, setHodTab] = useState('PENDING'); // 'PENDING', 'APPROVED', 'AUDIT'

  // New OD Form State
  const [formData, setFormData] = useState({
    submissionType: 'SOLO',
    eventType: 'Hackathon',
    eventName: '',
    eventDate: '2026-09-24',
    eventDay: 'Thursday',
    description: '',
    teamMembers: ['Aravindhan S (21IT101)'],
  });

  // Review Form Remarks
  const [reviewRemarks, setReviewRemarks] = useState('');

  // Result Form State
  const [resultData, setResultData] = useState({
    status: 'WON',
    projectName: '',
    description: '',
  });

  // Calculate day of week on date change
  const handleDateChange = (e) => {
    const d = new Date(e.target.value);
    const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    setFormData({
      ...formData,
      eventDate: e.target.value,
      eventDay: days[d.getDay()] || '',
    });
  };

  // Preset Quick Login
  const loginAs = (role) => {
    if (role === 'STUDENT') {
      setUser({
        name: 'Aravindhan S',
        email: 'aravindhan.21it@smvec.ac.in',
        role: 'STUDENT',
        rollNumber: '21IT101',
        year: 3,
        section: 'A',
        department: 'Information Technology',
      });
    } else if (role === 'ADVISOR') {
      setUser({
        name: 'Dr. K. Senthil',
        email: 'advisor.it3a@smvec.ac.in',
        role: 'ADVISOR',
        year: 3,
        section: 'A',
        department: 'Information Technology',
      });
    } else if (role === 'HOD') {
      setUser({
        name: 'Dr. P. Sivakumar',
        email: 'hod.it@smvec.ac.in',
        role: 'HOD',
        department: 'Information Technology',
      });
    }
  };

  // Submit New OD by Student
  const handleCreateOD = (e) => {
    e.preventDefault();
    if (!formData.eventName || !formData.description) return;

    const newId = `OD-2026-${String(requests.length + 1).padStart(3, '0')}`;
    const newReq = {
      id: newId,
      studentName: user.name,
      rollNumber: user.rollNumber,
      department: user.department,
      year: user.year,
      section: user.section,
      submissionType: formData.submissionType,
      teamMembers: formData.submissionType === 'TEAM' ? formData.teamMembers : [],
      eventType: formData.eventType,
      eventName: formData.eventName,
      eventDate: formData.eventDate,
      eventDay: formData.eventDay,
      description: formData.description,
      status: 'PENDING_ADVISOR',
      attachmentName: `Brochure_${formData.eventName.replace(/\s+/g, '_')}.pdf`,
      advisorRemarks: null,
      advisorName: null,
      advisorTimestamp: null,
      hodRemarks: null,
      hodName: null,
      hodTimestamp: null,
      resultStatus: 'PENDING',
      createdAt: 'Just now',
    };

    setRequests([newReq, ...requests]);
    setAuditLogs([
      {
        id: `AUD-${Date.now()}`,
        action: 'CREATED',
        actor: `${user.name} (${user.rollNumber})`,
        role: 'STUDENT',
        time: 'Just now',
        details: `Submitted OD request for ${formData.eventName}`,
      },
      ...auditLogs,
    ]);
    setNotifications([
      {
        id: `N-${Date.now()}`,
        title: 'New OD Submission 📋',
        text: `${user.name} submitted OD request for ${formData.eventName}.`,
        time: 'Just now',
        role: 'ADVISOR',
      },
      ...notifications,
    ]);

    setShowNewODModal(false);
    setFormData({
      submissionType: 'SOLO',
      eventType: 'Hackathon',
      eventName: '',
      eventDate: '2026-09-24',
      eventDay: 'Thursday',
      description: '',
      teamMembers: [user.name],
    });
  };

  // Class Advisor Forwards to HOD
  const handleAdvisorForward = (reqId) => {
    const remarks = reviewRemarks || 'Verified attendance > 80% and credentials. Forwarded for HOD sanction.';
    setRequests(
      requests.map((r) =>
        r.id === reqId
          ? {
              ...r,
              status: 'FORWARDED_HOD',
              advisorRemarks: remarks,
              advisorName: user.name,
              advisorTimestamp: 'Just now',
            }
          : r
      )
    );
    setAuditLogs([
      {
        id: `AUD-${Date.now()}`,
        action: 'FORWARDED',
        actor: user.name,
        role: 'ADVISOR',
        time: 'Just now',
        details: `Class Advisor recommended and forwarded ${reqId} to HOD: "${remarks}"`,
      },
      ...auditLogs,
    ]);
    setNotifications([
      {
        id: `N-${Date.now()}`,
        title: 'Request Forwarded to HOD ⚡',
        text: `${user.name} forwarded ${reqId} for final sanction.`,
        time: 'Just now',
        role: 'HOD',
      },
      {
        id: `N-${Date.now() + 1}`,
        title: 'Advisor Recommendation Approved ✅',
        text: `Your OD request ${reqId} was reviewed by Advisor and forwarded to HOD.`,
        time: 'Just now',
        role: 'STUDENT',
      },
      ...notifications,
    ]);
    setShowReviewModal(null);
    setReviewRemarks('');
  };

  // Class Advisor Rejects
  const handleAdvisorReject = (reqId) => {
    const remarks = reviewRemarks || 'Dates clash with internal assessments / Low attendance.';
    setRequests(
      requests.map((r) =>
        r.id === reqId
          ? {
              ...r,
              status: 'REJECTED_ADVISOR',
              advisorRemarks: remarks,
              advisorName: user.name,
              advisorTimestamp: 'Just now',
            }
          : r
      )
    );
    setAuditLogs([
      {
        id: `AUD-${Date.now()}`,
        action: 'REJECTED_BY_ADVISOR',
        actor: user.name,
        role: 'ADVISOR',
        time: 'Just now',
        details: `Class Advisor rejected ${reqId}: "${remarks}"`,
      },
      ...auditLogs,
    ]);
    setShowReviewModal(null);
    setReviewRemarks('');
  };

  // HOD Final Sanction
  const handleHodApprove = (reqId) => {
    const remarks = reviewRemarks || 'Sanctioned with full attendance compensation.';
    setRequests(
      requests.map((r) =>
        r.id === reqId
          ? {
              ...r,
              status: 'APPROVED',
              hodRemarks: remarks,
              hodName: user.name,
              hodTimestamp: 'Just now',
            }
          : r
      )
    );
    setAuditLogs([
      {
        id: `AUD-${Date.now()}`,
        action: 'APPROVED_BY_HOD',
        actor: user.name,
        role: 'HOD',
        time: 'Just now',
        details: `HOD granted final On-Duty approval for ${reqId}: "${remarks}"`,
      },
      ...auditLogs,
    ]);
    setNotifications([
      {
        id: `N-${Date.now()}`,
        title: '🎉 OD Sanctioned by HOD!',
        text: `Your OD request ${reqId} has received official HOD approval. OD Slip is now valid!`,
        time: 'Just now',
        role: 'STUDENT',
      },
      ...notifications,
    ]);
    setShowReviewModal(null);
    setReviewRemarks('');
  };

  // HOD Rejection
  const handleHodReject = (reqId) => {
    const remarks = reviewRemarks || 'Department quota exceeded / Non-essential event.';
    setRequests(
      requests.map((r) =>
        r.id === reqId
          ? {
              ...r,
              status: 'REJECTED_HOD',
              hodRemarks: remarks,
              hodName: user.name,
              hodTimestamp: 'Just now',
            }
          : r
      )
    );
    setShowReviewModal(null);
    setReviewRemarks('');
  };

  // Submit Post-Event Result
  const handleSaveResult = (e) => {
    e.preventDefault();
    if (!showResultModal) return;

    setRequests(
      requests.map((r) =>
        r.id === showResultModal.id
          ? {
              ...r,
              resultStatus: resultData.status,
              resultProjectName: resultData.projectName || r.eventName,
              resultDescription: resultData.description,
              resultCertificate: `Certificate_${r.id}.pdf`,
            }
          : r
      )
    );
    setShowResultModal(null);
    setResultData({ status: 'WON', projectName: '', description: '' });
  };

  // Export CSV Report
  const handleExportCSV = () => {
    const headers = ['OD_ID', 'Student_Name', 'Roll_No', 'Year', 'Section', 'Event_Type', 'Event_Name', 'Event_Date', 'Status', 'Advisor', 'HOD_Approval'];
    const rows = requests.map((r) => [
      r.id,
      r.studentName,
      r.rollNumber,
      r.year,
      r.section,
      r.eventType,
      `"${r.eventName}"`,
      r.eventDate,
      r.status,
      r.advisorName || 'Pending',
      r.hodName || 'Pending',
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
  // RENDER: LOGIN VIEW (if unauthenticated)
  // -------------------------------------------------------------
  if (!user) {
    return (
      <div className={styles.appContainer}>
        {/* Simple Top Bar */}
        <header className={styles.topNav}>
          <div className={styles.topNavInner}>
            <Link href="/" className={styles.brandGroup}>
              <img src="/college_logo.png" alt="SMVEC Logo" className={styles.brandLogo} />
              <div className={styles.brandInfo}>
                <span className={styles.brandTitle}>SMVEC OD PORTAL</span>
                <span className={styles.brandSubtitle}>IT Department · Puducherry</span>
              </div>
            </Link>
            <div className={styles.navActions}>
              <a href="/downloads/smvec-od.apk" download="smvec-od.apk" className={styles.navLinkBtn}>
                📱 Download APK (~39 MB)
              </a>
              <Link href="/" className={styles.navLinkBtn}>
                ← Back to Landing Page
              </Link>
            </div>
          </div>
        </header>

        {/* Login Card */}
        <div className={styles.authContainer}>
          <div className={styles.authCard}>
            <img src="/college_logo.png" alt="SMVEC Logo" className={styles.authHeaderLogo} />
            <h1 className={styles.authTitle}>Role-Based OD Portal</h1>
            <p className={styles.authSubtitle}>
              Reference Architecture: Student ➔ Class Advisor ➔ HOD Final Sanction
            </p>

            {/* Quick Demo Login Presets */}
            <div className={styles.quickPresets}>
              <div className={styles.quickPresetsTitle}>⚡ Instant One-Click Demo Access</div>
              <div className={styles.presetButtons}>
                <button className={styles.presetBtn} onClick={() => loginAs('STUDENT')} id="btn-login-student">
                  🎓 Student
                  <br />
                  <span style={{ fontSize: '0.65rem', color: '#64748b' }}>Aravindhan (21IT101)</span>
                </button>
                <button className={styles.presetBtn} onClick={() => loginAs('ADVISOR')} id="btn-login-advisor">
                  👩‍🏫 Class Advisor
                  <br />
                  <span style={{ fontSize: '0.65rem', color: '#64748b' }}>Dr. K. Senthil (IT-III-A)</span>
                </button>
                <button className={styles.presetBtn} onClick={() => loginAs('HOD')} id="btn-login-hod">
                  👨‍💼 HOD
                  <br />
                  <span style={{ fontSize: '0.65rem', color: '#64748b' }}>Dr. P. Sivakumar</span>
                </button>
              </div>
            </div>

            <div style={{ height: '1px', background: '#e5e7eb', margin: '20px 0' }} />

            {/* Manual Form */}
            <form
              className={styles.authForm}
              onSubmit={(e) => {
                e.preventDefault();
                loginAs('STUDENT');
              }}
            >
              <div className={styles.formGroup}>
                <label className={styles.formLabel}>College Email ID (@smvec.ac.in)</label>
                <input
                  type="email"
                  className={styles.formInput}
                  defaultValue="student@smvec.ac.in"
                  placeholder="name.roll@smvec.ac.in"
                  required
                />
              </div>

              <div className={styles.formGroup}>
                <label className={styles.formLabel}>Password / College SSO</label>
                <input
                  type="password"
                  className={styles.formInput}
                  defaultValue="password123"
                  placeholder="••••••••"
                  required
                />
              </div>

              <button type="submit" className={styles.authSubmitBtn}>
                Login to Portal →
              </button>
            </form>
          </div>
        </div>
      </div>
    );
  }

  // -------------------------------------------------------------
  // RENDER: AUTHENTICATED DASHBOARDS
  // -------------------------------------------------------------
  const userRequests = requests.filter(
    (r) => r.rollNumber === user.rollNumber || r.studentName === user.name
  );
  const classRequests = requests.filter((r) => r.year === 3 && r.section === 'A');
  const forwardedToHod = requests.filter((r) => r.status === 'FORWARDED_HOD');
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
                {user.role === 'ADVISOR' && '👩‍🏫 Class Advisor Portal'}
                {user.role === 'HOD' && '👨‍💼 HOD Executive Portal'}
              </span>
            </div>
          </Link>

          <div className={styles.navActions}>
            {/* Role Switcher in Nav for Evaluator Convenience */}
            <div style={{ display: 'flex', gap: '6px' }}>
              <button
                onClick={() => loginAs('STUDENT')}
                style={{
                  padding: '4px 8px',
                  fontSize: '0.72rem',
                  fontWeight: user.role === 'STUDENT' ? 'bold' : 'normal',
                  background: user.role === 'STUDENT' ? '#3350b0' : '#f3f4f6',
                  color: user.role === 'STUDENT' ? '#fff' : '#4b5563',
                  border: '1px solid #d1d5db',
                  borderRadius: '6px',
                  cursor: 'pointer',
                }}
              >
                Student View
              </button>
              <button
                onClick={() => loginAs('ADVISOR')}
                style={{
                  padding: '4px 8px',
                  fontSize: '0.72rem',
                  fontWeight: user.role === 'ADVISOR' ? 'bold' : 'normal',
                  background: user.role === 'ADVISOR' ? '#3350b0' : '#f3f4f6',
                  color: user.role === 'ADVISOR' ? '#fff' : '#4b5563',
                  border: '1px solid #d1d5db',
                  borderRadius: '6px',
                  cursor: 'pointer',
                }}
              >
                Advisor View
              </button>
              <button
                onClick={() => loginAs('HOD')}
                style={{
                  padding: '4px 8px',
                  fontSize: '0.72rem',
                  fontWeight: user.role === 'HOD' ? 'bold' : 'normal',
                  background: user.role === 'HOD' ? '#3350b0' : '#f3f4f6',
                  color: user.role === 'HOD' ? '#fff' : '#4b5563',
                  border: '1px solid #d1d5db',
                  borderRadius: '6px',
                  cursor: 'pointer',
                }}
              >
                HOD View
              </button>
            </div>

            <span
              className={`${styles.roleBadge} ${
                user.role === 'STUDENT'
                  ? styles.roleBadgeStudent
                  : user.role === 'ADVISOR'
                  ? styles.roleBadgeAdvisor
                  : styles.roleBadgeHod
              }`}
            >
              ● {user.name} ({user.role})
            </span>

            {/* Notification Bell */}
            <button
              className={styles.notifBtn}
              onClick={() => setShowNotifDrawer(true)}
              title="Notifications"
            >
              🔔
              <span className={styles.notifBadge}>{notifications.length}</span>
            </button>

            {/* Download APK Link */}
            <a
              href="/downloads/smvec-od.apk"
              download="smvec-od.apk"
              className={styles.navLinkBtn}
              title="Download Android Mobile App"
            >
              📱 APK
            </a>

            <button className={styles.logoutBtn} onClick={() => setUser(null)}>
              Logout
            </button>
          </div>
        </div>
      </header>

      {/* Main Body */}
      <main className={styles.mainArea}>
        {/* ========================================================= */}
        {/* 1. STUDENT VIEW */}
        {/* ========================================================= */}
        {user.role === 'STUDENT' && (
          <div>
            {/* Banner */}
            <div className={styles.portalBanner}>
              <div>
                <h2 className={styles.bannerTitle}>Welcome back, {user.name}!</h2>
                <p className={styles.bannerSub}>
                  Roll No: <strong>{user.rollNumber}</strong> · Year {user.year} - Sec {user.section} · Dept of {user.department}
                </p>
              </div>
              <button
                className={styles.bannerActionBtn}
                onClick={() => setShowNewODModal(true)}
                id="btn-apply-od"
              >
                ➕ Apply New OD Request
              </button>
            </div>

            {/* KPI Cards */}
            <div className={styles.kpiGrid}>
              <div className={styles.kpiCard}>
                <div className={styles.kpiIcon} style={{ background: '#eff6ff', color: '#1d4ed8' }}>
                  📁
                </div>
                <div>
                  <div className={styles.kpiNumber}>{userRequests.length}</div>
                  <div className={styles.kpiLabel}>Total OD Requests</div>
                </div>
              </div>
              <div className={styles.kpiCard}>
                <div className={styles.kpiIcon} style={{ background: '#fffbeb', color: '#d97706' }}>
                  ⏳
                </div>
                <div>
                  <div className={styles.kpiNumber}>
                    {userRequests.filter((r) => r.status === 'PENDING_ADVISOR' || r.status === 'FORWARDED_HOD').length}
                  </div>
                  <div className={styles.kpiLabel}>In Review Pipeline</div>
                </div>
              </div>
              <div className={styles.kpiCard}>
                <div className={styles.kpiIcon} style={{ background: '#ecfdf5', color: '#059669' }}>
                  ✅
                </div>
                <div>
                  <div className={styles.kpiNumber}>
                    {userRequests.filter((r) => r.status === 'APPROVED').length}
                  </div>
                  <div className={styles.kpiLabel}>Approved ODs</div>
                </div>
              </div>
              <div className={styles.kpiCard}>
                <div className={styles.kpiIcon} style={{ background: '#fdf2f8', color: '#db2777' }}>
                  🏆
                </div>
                <div>
                  <div className={styles.kpiNumber}>
                    {userRequests.filter((r) => r.resultStatus !== 'PENDING').length}
                  </div>
                  <div className={styles.kpiLabel}>Results Submitted</div>
                </div>
              </div>
            </div>

            {/* Requests List */}
            <div className={styles.cardSection}>
              <div className={styles.cardSectionHeader}>
                <h3 className={styles.sectionHeading}>My On-Duty Submissions</h3>
                <span style={{ fontSize: '0.85rem', color: '#6b7280' }}>
                  Showing {userRequests.length} applications
                </span>
              </div>

              {userRequests.length === 0 ? (
                <p style={{ textAlign: 'center', padding: '30px', color: '#9ca3af' }}>
                  No OD applications yet. Click "Apply New OD Request" to begin!
                </p>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                  {userRequests.map((req) => (
                    <div
                      key={req.id}
                      style={{
                        background: '#ffffff',
                        border: '1px solid #e5e7eb',
                        borderRadius: '14px',
                        padding: '20px',
                        boxShadow: '0 2px 8px rgba(0,0,0,0.03)',
                      }}
                    >
                      {/* Request Header */}
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: '10px' }}>
                        <div>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '6px' }}>
                            <span
                              style={{
                                background: '#eff6ff',
                                color: '#1d4ed8',
                                padding: '3px 8px',
                                borderRadius: '6px',
                                fontSize: '0.72rem',
                                fontWeight: '700',
                              }}
                            >
                              {req.eventType.toUpperCase()}
                            </span>
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
                            <span>📎 Attachment: <em>{req.attachmentName}</em></span>
                          </div>
                        </div>

                        {/* Status Badge */}
                        <div>
                          {req.status === 'APPROVED' && (
                            <span className={`${styles.statusBadge} ${styles.statusApproved}`}>
                              ✓ HOD Approved (OD Granted)
                            </span>
                          )}
                          {req.status === 'FORWARDED_HOD' && (
                            <span className={`${styles.statusBadge} ${styles.statusForwarded}`}>
                              ⏳ Forwarded to HOD
                            </span>
                          )}
                          {req.status === 'PENDING_ADVISOR' && (
                            <span className={`${styles.statusBadge} ${styles.statusPending}`}>
                              ⏳ Under Advisor Review
                            </span>
                          )}
                          {(req.status === 'REJECTED_ADVISOR' || req.status === 'REJECTED_HOD') && (
                            <span className={`${styles.statusBadge} ${styles.statusRejected}`}>
                              ✕ Rejected
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
                                : req.status === 'FORWARDED_HOD' || req.status === 'APPROVED'
                                ? styles.stepCircleDone
                                : styles.stepCircleActive
                            }`}
                          >
                            {req.status === 'REJECTED_ADVISOR' ? '✕' : req.status === 'FORWARDED_HOD' || req.status === 'APPROVED' ? '✓' : '2'}
                          </div>
                          <span className={styles.stepLabel}>2. Class Advisor</span>
                        </div>
                        <div className={`${styles.stepDivider} ${req.status === 'APPROVED' ? styles.stepDividerDone : ''}`} />
                        <div className={styles.stepItem}>
                          <div
                            className={`${styles.stepCircle} ${
                              req.status === 'REJECTED_HOD'
                                ? styles.stepCircleRejected
                                : req.status === 'APPROVED'
                                ? styles.stepCircleDone
                                : req.status === 'FORWARDED_HOD'
                                ? styles.stepCircleActive
                                : styles.stepCirclePending
                            }`}
                          >
                            {req.status === 'REJECTED_HOD' ? '✕' : req.status === 'APPROVED' ? '✓' : '3'}
                          </div>
                          <span className={styles.stepLabel}>3. HOD Decision</span>
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
                          <span className={styles.stepLabel}>4. OD Sanctioned</span>
                        </div>
                      </div>

                      {/* Description */}
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
                              👩‍🏫 Advisor Note ({req.advisorName}):
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
                              👨‍💼 HOD Sanction ({req.hodName}):
                            </span>
                            <div style={{ color: '#047857', marginTop: '2px' }}>{req.hodRemarks}</div>
                          </div>
                        )}
                      </div>

                      {/* Post-Event Result Section */}
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
                              🏆 <strong>Result Submitted:</strong> {req.resultStatus} —{' '}
                              <em>{req.resultProjectName}</em> (Certificate verified)
                            </div>
                          ) : (
                            <div style={{ fontSize: '0.85rem', color: '#6b7280' }}>
                              Event completed? Submit your awards & certificates for college records.
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
            {/* Banner */}
            <div className={styles.portalBanner}>
              <div>
                <h2 className={styles.bannerTitle}>Class Advisor Dashboard</h2>
                <p className={styles.bannerSub}>
                  {user.name} · Department of {user.department} · Class: <strong>Year {user.year} - Section {user.section}</strong>
                </p>
              </div>
              <div style={{ fontSize: '0.85rem', background: 'rgba(255,255,255,0.2)', padding: '8px 16px', borderRadius: '8px' }}>
                Class In-Charge: 64 Students
              </div>
            </div>

            {/* Filter Tabs */}
            <div style={{ display: 'flex', gap: '8px', marginBottom: '20px', flexWrap: 'wrap' }}>
              <button
                className={`${styles.roleTab} ${advisorFilter === 'ALL' ? styles.roleTabActive : ''}`}
                style={{ flex: 'none', padding: '8px 16px', border: '1px solid #e5e7eb' }}
                onClick={() => setAdvisorFilter('ALL')}
              >
                All Class Submissions ({classRequests.length})
              </button>
              <button
                className={`${styles.roleTab} ${advisorFilter === 'PENDING' ? styles.roleTabActive : ''}`}
                style={{ flex: 'none', padding: '8px 16px', border: '1px solid #e5e7eb' }}
                onClick={() => setAdvisorFilter('PENDING')}
              >
                Pending My Review ({classRequests.filter((r) => r.status === 'PENDING_ADVISOR').length})
              </button>
              <button
                className={`${styles.roleTab} ${advisorFilter === 'FORWARDED' ? styles.roleTabActive : ''}`}
                style={{ flex: 'none', padding: '8px 16px', border: '1px solid #e5e7eb' }}
                onClick={() => setAdvisorFilter('FORWARDED')}
              >
                Forwarded to HOD ({classRequests.filter((r) => r.status === 'FORWARDED_HOD' || r.status === 'APPROVED').length})
              </button>
              <button
                className={`${styles.roleTab} ${advisorFilter === 'REJECTED' ? styles.roleTabActive : ''}`}
                style={{ flex: 'none', padding: '8px 16px', border: '1px solid #e5e7eb' }}
                onClick={() => setAdvisorFilter('REJECTED')}
              >
                Rejected by Me ({classRequests.filter((r) => r.status === 'REJECTED_ADVISOR').length})
              </button>
            </div>

            {/* Submissions Table / Cards */}
            <div className={styles.cardSection}>
              <h3 className={styles.sectionHeading} style={{ marginBottom: '16px' }}>
                Submissions from Year {user.year} - Sec {user.section}
              </h3>

              <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
                {classRequests
                  .filter((r) => {
                    if (advisorFilter === 'PENDING') return r.status === 'PENDING_ADVISOR';
                    if (advisorFilter === 'FORWARDED') return r.status === 'FORWARDED_HOD' || r.status === 'APPROVED';
                    if (advisorFilter === 'REJECTED') return r.status === 'REJECTED_ADVISOR';
                    return true;
                  })
                  .map((req) => (
                    <div
                      key={req.id}
                      style={{
                        padding: '16px',
                        border: req.status === 'PENDING_ADVISOR' ? '2px solid #f59e0b' : '1px solid #e5e7eb',
                        borderRadius: '12px',
                        background: '#ffffff',
                      }}
                    >
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: '10px' }}>
                        <div>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                            <span style={{ fontWeight: '800', fontSize: '1rem', color: '#1e293b' }}>
                              {req.studentName}
                            </span>
                            <span style={{ fontSize: '0.8rem', color: '#6b7280' }}>
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
                          <div style={{ fontSize: '0.95rem', fontWeight: '700', color: '#3350b0', margin: '4px 0' }}>
                            {req.eventName} ({req.eventType})
                          </div>
                          <div style={{ fontSize: '0.82rem', color: '#6b7280' }}>
                            📅 Date: {req.eventDate} ({req.eventDay}) · 📎 Attachment: {req.attachmentName}
                          </div>
                        </div>

                        <div>
                          {req.status === 'PENDING_ADVISOR' ? (
                            <span className={`${styles.statusBadge} ${styles.statusPending}`}>
                              ⏳ Needs Your Review
                            </span>
                          ) : req.status === 'FORWARDED_HOD' ? (
                            <span className={`${styles.statusBadge} ${styles.statusForwarded}`}>
                              Forwarded to HOD
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

                      {req.teamMembers.length > 0 && (
                        <div style={{ fontSize: '0.8rem', color: '#6b7280', marginBottom: '10px' }}>
                          👥 <strong>Team Members:</strong> {req.teamMembers.join(', ')}
                        </div>
                      )}

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
                              Reject with Reason
                            </button>
                            <button
                              style={{
                                padding: '8px 18px',
                                background: '#3350b0',
                                color: '#ffffff',
                                border: 'none',
                                borderRadius: '8px',
                                fontSize: '0.82rem',
                                fontWeight: '700',
                                cursor: 'pointer',
                              }}
                              onClick={() => {
                                setShowReviewModal(req);
                                setReviewRemarks('Verified attendance > 80% and credentials. Forwarded for HOD sanction.');
                              }}
                            >
                              Review & Forward to HOD →
                            </button>
                          </>
                        ) : (
                          <div style={{ fontSize: '0.8rem', color: '#6b7280' }}>
                            Your Remarks: <em>{req.advisorRemarks || 'No remarks'}</em>
                          </div>
                        )}
                      </div>
                    </div>
                  ))}
              </div>
            </div>
          </div>
        )}

        {/* ========================================================= */}
        {/* 3. HOD VIEW */}
        {/* ========================================================= */}
        {user.role === 'HOD' && (
          <div>
            {/* Banner */}
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
                📥 Export Department OD Report (CSV/Excel)
              </button>
            </div>

            {/* HOD KPI Metrics */}
            <div className={styles.kpiGrid}>
              <div className={styles.kpiCard}>
                <div className={styles.kpiIcon} style={{ background: '#eff6ff', color: '#1d4ed8' }}>
                  📊
                </div>
                <div>
                  <div className={styles.kpiNumber}>{requests.length}</div>
                  <div className={styles.kpiLabel}>Total Submissions</div>
                </div>
              </div>
              <div className={styles.kpiCard}>
                <div className={styles.kpiIcon} style={{ background: '#eff6ff', color: '#2563eb' }}>
                  ⚡
                </div>
                <div>
                  <div className={styles.kpiNumber}>{forwardedToHod.length}</div>
                  <div className={styles.kpiLabel}>Awaiting HOD Decision</div>
                </div>
              </div>
              <div className={styles.kpiCard}>
                <div className={styles.kpiIcon} style={{ background: '#ecfdf5', color: '#059669' }}>
                  ✅
                </div>
                <div>
                  <div className={styles.kpiNumber}>{approvedRequests.length}</div>
                  <div className={styles.kpiLabel}>Officially Sanctioned</div>
                </div>
              </div>
              <div className={styles.kpiCard}>
                <div className={styles.kpiIcon} style={{ background: '#fef2f2', color: '#dc2626' }}>
                  ✕
                </div>
                <div>
                  <div className={styles.kpiNumber}>
                    {requests.filter((r) => r.status.includes('REJECTED')).length}
                  </div>
                  <div className={styles.kpiLabel}>Total Rejected</div>
                </div>
              </div>
            </div>

            {/* Tab Navigation */}
            <div style={{ display: 'flex', gap: '8px', marginBottom: '20px' }}>
              <button
                className={`${styles.roleTab} ${hodTab === 'PENDING' ? styles.roleTabActive : ''}`}
                style={{ flex: 'none', padding: '8px 20px', border: '1px solid #e5e7eb' }}
                onClick={() => setHodTab('PENDING')}
              >
                Forwarded from Advisors ({forwardedToHod.length})
              </button>
              <button
                className={`${styles.roleTab} ${hodTab === 'APPROVED' ? styles.roleTabActive : ''}`}
                style={{ flex: 'none', padding: '8px 20px', border: '1px solid #e5e7eb' }}
                onClick={() => setHodTab('APPROVED')}
              >
                Sanctioned Archive ({approvedRequests.length})
              </button>
              <button
                className={`${styles.roleTab} ${hodTab === 'AUDIT' ? styles.roleTabActive : ''}`}
                style={{ flex: 'none', padding: '8px 20px', border: '1px solid #e5e7eb' }}
                onClick={() => setHodTab('AUDIT')}
              >
                Immutable Audit Trail ({auditLogs.length})
              </button>
            </div>

            {/* TAB 1: Forwarded Submissions (Ready for Final Decision) */}
            {hodTab === 'PENDING' && (
              <div className={styles.cardSection}>
                <h3 className={styles.sectionHeading} style={{ marginBottom: '16px' }}>
                  Forwarded by Class Advisors (Awaiting Official Approval)
                </h3>

                {forwardedToHod.length === 0 ? (
                  <p style={{ textAlign: 'center', padding: '30px', color: '#10b981', fontWeight: '600' }}>
                    ✓ All caught up! No requests currently waiting for HOD sanction.
                  </p>
                ) : (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                    {forwardedToHod.map((req) => (
                      <div
                        key={req.id}
                        style={{
                          padding: '20px',
                          border: '2px solid #2563eb',
                          borderRadius: '14px',
                          background: '#ffffff',
                          boxShadow: '0 4px 12px rgba(37,99,235,0.06)',
                        }}
                      >
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: '10px' }}>
                          <div>
                            <span style={{ fontSize: '0.75rem', fontWeight: '800', color: '#2563eb', textTransform: 'uppercase' }}>
                              Forwarded by Class Advisor ({req.advisorName})
                            </span>
                            <h4 style={{ fontSize: '1.2rem', fontWeight: '800', color: '#1e293b', margin: '4px 0' }}>
                              {req.studentName} (Roll: {req.rollNumber})
                            </h4>
                            <div style={{ fontSize: '0.85rem', color: '#6b7280' }}>
                              Year {req.year} - Section {req.section} · {req.department}
                            </div>
                          </div>

                          <span className={`${styles.statusBadge} ${styles.statusForwarded}`}>
                            ⚡ Ready for HOD Sanction
                          </span>
                        </div>

                        <div style={{ background: '#f8fafc', padding: '12px', borderRadius: '8px', margin: '14px 0' }}>
                          <div style={{ fontSize: '0.95rem', fontWeight: '700', color: '#3350b0' }}>
                            {req.eventName} ({req.eventType})
                          </div>
                          <div style={{ fontSize: '0.82rem', color: '#4b5563', marginTop: '4px' }}>
                            📅 Date: {req.eventDate} ({req.eventDay}) · Attachment: {req.attachmentName}
                          </div>
                          <p style={{ fontSize: '0.85rem', color: '#334155', marginTop: '6px' }}>
                            {req.description}
                          </p>
                        </div>

                        {/* Advisor recommendation note */}
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
                            Class Advisor Recommendation ({req.advisorName}):
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
                              padding: '8px 24px',
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
                          >
                            ✓ Officially Sanction OD
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
                          {req.studentName} ({req.rollNumber}) — {req.eventName}
                        </div>
                        <div style={{ fontSize: '0.8rem', color: '#047857' }}>
                          Sanctioned by {req.hodName} on {req.eventDate} ({req.eventType}) · {req.submissionType}
                        </div>
                      </div>
                      <span className={`${styles.statusBadge} ${styles.statusApproved}`}>
                        Official OD Valid ✓
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* TAB 3: Immutable Audit Trail */}
            {hodTab === 'AUDIT' && (
              <div className={styles.cardSection}>
                <h3 className={styles.sectionHeading} style={{ marginBottom: '16px' }}>
                  System Audit Trail & Decision Log
                </h3>

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
                            log.action === 'APPROVED' || log.action === 'APPROVED_BY_HOD'
                              ? '#059669'
                              : log.action === 'FORWARDED'
                              ? '#2563eb'
                              : log.action.includes('REJECTED')
                              ? '#dc2626'
                              : '#3350b0',
                        }}
                      />
                      <div style={{ flex: 1 }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                          <span style={{ fontSize: '0.85rem', fontWeight: '700', color: '#1e293b' }}>
                            [{log.role}] {log.actor} — {log.action.replace(/_/g, ' ')}
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
              </div>
            )}
          </div>
        )}
      </main>

      {/* ========================================================= */}
      {/* NOTIFICATION DRAWER */}
      {/* ========================================================= */}
      {showNotifDrawer && (
        <div className={styles.notifDrawer}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <h3 style={{ fontSize: '1.1rem', fontWeight: '800' }}>🔔 In-App Notifications</h3>
            <button
              onClick={() => setShowNotifDrawer(false)}
              style={{ background: 'transparent', border: 'none', fontSize: '1.2rem', cursor: 'pointer' }}
            >
              ✕
            </button>
          </div>
          <div className={styles.notifList}>
            {notifications.map((n) => (
              <div key={n.id} className={styles.notifItem}>
                <div className={styles.notifItemTitle}>{n.title}</div>
                <div className={styles.notifItemText}>{n.text}</div>
                <div className={styles.notifItemTime}>{n.time}</div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* ========================================================= */}
      {/* MODAL: CREATE NEW OD REQUEST (STUDENT) */}
      {/* ========================================================= */}
      {showNewODModal && (
        <div className={styles.modalBackdrop}>
          <div className={styles.modalBox}>
            <div className={styles.modalHeader}>
              <h3 className={styles.modalTitle}>Submit On-Duty Application</h3>
              <button className={styles.closeModalBtn} onClick={() => setShowNewODModal(false)}>
                ✕
              </button>
            </div>

            <form onSubmit={handleCreateOD}>
              {/* Solo / Team */}
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
                    👥 Team (Up to 5)
                  </button>
                </div>
              </div>

              {/* Event Type */}
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

              {/* Event Name */}
              <div className={styles.formGroup} style={{ marginBottom: '14px' }}>
                <label className={styles.formLabel}>Event Name & Organizer</label>
                <input
                  type="text"
                  className={styles.formInput}
                  placeholder="e.g. Smart India Hackathon / IIT Madras Shaastra"
                  value={formData.eventName}
                  onChange={(e) => setFormData({ ...formData, eventName: e.target.value })}
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
                  <label className={styles.formLabel}>Calculated Day</label>
                  <input
                    type="text"
                    className={styles.formInput}
                    value={formData.eventDay}
                    readOnly
                    style={{ background: '#f3f4f6', color: '#4b5563' }}
                  />
                </div>
              </div>

              {/* Description */}
              <div className={styles.formGroup} style={{ marginBottom: '14px' }}>
                <label className={styles.formLabel}>Detailed Purpose / Project Title</label>
                <textarea
                  className={styles.formInput}
                  rows={3}
                  placeholder="Explain event agenda, venue location, team role, and relevance..."
                  value={formData.description}
                  onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                  required
                />
              </div>

              {/* Attachment */}
              <div className={styles.formGroup} style={{ marginBottom: '20px' }}>
                <label className={styles.formLabel}>Document Attachment (Invitation / Brochure)</label>
                <div
                  style={{
                    padding: '14px',
                    border: '2px dashed #cbd5e1',
                    borderRadius: '10px',
                    textAlign: 'center',
                    background: '#f8fafc',
                    fontSize: '0.85rem',
                    color: '#64748b',
                  }}
                >
                  📄 Event_Brochure_Invitation.pdf (Auto-attached demo file)
                </div>
              </div>

              <button type="submit" className={styles.authSubmitBtn} style={{ width: '100%' }}>
                Submit to Class Advisor for Review →
              </button>
            </form>
          </div>
        </div>
      )}

      {/* ========================================================= */}
      {/* MODAL: ADVISOR / HOD REVIEW MODAL */}
      {/* ========================================================= */}
      {showReviewModal && (
        <div className={styles.modalBackdrop}>
          <div className={styles.modalBox}>
            <div className={styles.modalHeader}>
              <h3 className={styles.modalTitle}>Review Submission #{showReviewModal.id}</h3>
              <button className={styles.closeModalBtn} onClick={() => setShowReviewModal(null)}>
                ✕
              </button>
            </div>

            <div>
              <p>
                <strong>Student:</strong> {showReviewModal.studentName} ({showReviewModal.rollNumber})
              </p>
              <p>
                <strong>Event:</strong> {showReviewModal.eventName} ({showReviewModal.eventType})
              </p>
              <p>
                <strong>Date:</strong> {showReviewModal.eventDate} ({showReviewModal.eventDay})
              </p>
              <p style={{ marginTop: '8px', color: '#4b5563' }}>
                <strong>Description:</strong> {showReviewModal.description}
              </p>

              <div style={{ marginTop: '16px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
                <label className={styles.formLabel}>Official Remarks / Feedback:</label>
                <textarea
                  className={styles.formInput}
                  rows={3}
                  value={reviewRemarks}
                  onChange={(e) => setReviewRemarks(e.target.value)}
                  placeholder="Enter evaluation, attendance validation, or rejection remarks..."
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
                      padding: '10px 20px',
                      background: '#3350b0',
                      color: '#ffffff',
                      border: 'none',
                      borderRadius: '8px',
                      fontWeight: '700',
                      cursor: 'pointer',
                    }}
                    onClick={() => handleAdvisorForward(showReviewModal.id)}
                  >
                    Forward to HOD →
                  </button>
                ) : (
                  <button
                    style={{
                      padding: '10px 20px',
                      background: '#059669',
                      color: '#ffffff',
                      border: 'none',
                      borderRadius: '8px',
                      fontWeight: '700',
                      cursor: 'pointer',
                    }}
                    onClick={() => handleHodApprove(showReviewModal.id)}
                  >
                    ✓ Officially Sanction OD
                  </button>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ========================================================= */}
      {/* MODAL: POST-EVENT RESULT SUBMISSION (STUDENT) */}
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
                  placeholder="e.g. AI Crop Vision System"
                  required
                />
              </div>

              <div className={styles.formGroup} style={{ marginBottom: '20px' }}>
                <label className={styles.formLabel}>Certificate / Event Photo</label>
                <div
                  style={{
                    padding: '14px',
                    border: '2px dashed #cbd5e1',
                    borderRadius: '10px',
                    textAlign: 'center',
                    background: '#f8fafc',
                    fontSize: '0.85rem',
                    color: '#64748b',
                  }}
                >
                  📜 Certificate_Proof_{showResultModal.id}.pdf (Attached)
                </div>
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
