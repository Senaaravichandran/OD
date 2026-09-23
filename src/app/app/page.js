'use client';

// The web portal for the SMVEC OD system.
//
// It is the same product as the Android app, not a cut-down view of it: the
// same three roles, the same sign-in routes, the same attachments, the same
// reports and exports. Both talk to /api/v2, which is where a feature is
// actually defined - this file only draws it.
//
// The portal holds no session of its own for students: every call carries a
// fresh Firebase ID token and the server decides what the caller may do. A
// staff member who signs in with a password gets a signed token from the
// server, which portal-api.js keeps.

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import {
  describeAuthError, firebaseReady, signInWithGoogle, signOut, watchAuth,
} from '@/lib/firebase-client';
import {
  api, apiPublic, clearStaffSession, hasStaffSession, loadStaffSession, setStaffSession,
} from '@/lib/portal-api';
import {
  FILE_KINDS, deleteFile, fileUrl, humanSize, kindLabel, uploadFile,
} from '@/lib/portal-upload';
import { EXPORTERS, gather } from '@/lib/portal-export';
import styles from './app.module.css';

const DOMAIN = '@smvec.ac.in';
const YEARS = [1, 2, 3, 4];
const SECTIONS = ['A', 'B', 'C', 'D', 'E', 'F'];
const EVENT_TYPES = ['Hackathon', 'Internship', 'Paper Presentation', 'Workshop', 'Symposium', 'Sports', 'Other'];
const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

const STATUS = {
  PENDING_ADVISOR: { label: 'Pending advisor', tone: 'pending' },
  APPROVED_BY_ADVISOR: { label: 'Awaiting HOD', tone: 'forwarded' },
  REJECTED_ADVISOR: { label: 'Rejected by advisor', tone: 'rejected' },
  APPROVED: { label: 'Approved', tone: 'approved' },
  REJECTED_HOD: { label: 'Rejected by HOD', tone: 'rejected' },
};

/// What a result has to be backed by. A supporting document stays optional,
/// being the one attachment that is not always relevant. The server applies
/// the same rule, so this only lets the button explain itself.
const evidenceFor = (status) => (status === 'WON'
  ? ['CERTIFICATE', 'EVENT_PHOTO', 'WINNING_PHOTO']
  : ['CERTIFICATE', 'EVENT_PHOTO']);

const fmtDate = (iso) => (iso ? new Date(iso).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : '');
const fmtTime = (iso) => (iso ? new Date(iso).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '');
const fmtRange = (r) => (r.eventEndDate && r.eventEndDate !== r.eventDate
  ? `${fmtDate(r.eventDate)} – ${fmtDate(r.eventEndDate)} (${r.dayCount || 1} days)`
  : fmtDate(r.eventDate));

/// The last day an OD covers, from its first day and how long it runs. Done in
/// UTC so a browser east or west of the server cannot shift it a day.
function addDays(iso, days) {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function PortalPage() {
  // Read from the build-time config, so it is settled before the first paint
  // and there is nothing to discover in an effect.
  const configured = firebaseReady();

  const [role, setRole] = useState(null); // which door they picked
  const [firebaseUser, setFirebaseUser] = useState(configured ? undefined : null);
  const [session, setSession] = useState(null);
  const [pending, setPending] = useState(null); // { email, name } for a new profile
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  // Whether the stored staff token has been checked yet, so the page does
  // not flash the role picker at someone who is already signed in.
  const [staffChecked, setStaffChecked] = useState(false);

  // A staff password session survives a reload, so look for one before
  // deciding anybody is signed out. The token is read at render time, which
  // keeps the effect to the one thing it is for: asking the server.
  const restoring = hasStaffSession() || Boolean(loadStaffSession());

  useEffect(() => {
    if (!restoring) return undefined;
    let cancelled = false;
    (async () => {
      try {
        const res = await api('SESSION');
        if (!cancelled) setSession({ user: res.user });
      } catch {
        // The token has expired or been revoked; start again.
        clearStaffSession();
      } finally {
        if (!cancelled) setStaffChecked(true);
      }
    })();
    return () => { cancelled = true; };
  }, [restoring]);

  // Firebase tells us whether anyone is signed in, including after a reload.
  // Signing out clears the profile here rather than in a second effect, so the
  // two never disagree for a render.
  useEffect(() => {
    if (!configured) return undefined;
    return watchAuth((user) => {
      setFirebaseUser(user);
      if (!user && !hasStaffSession()) {
        setSession(null);
        setPending(null);
      }
    });
  }, [configured]);

  // Once Firebase has a user, ask the server who they are.
  useEffect(() => {
    if (!firebaseUser || hasStaffSession()) return undefined;

    let cancelled = false;
    (async () => {
      setBusy(true);
      try {
        const res = await api('SESSION');
        if (cancelled) return;
        if (res.needsRegistration) {
          setPending({ email: res.email || '', name: res.name || '' });
          setSession(null);
        } else {
          setSession({ user: res.user });
          setPending(null);
        }
        setError('');
      } catch (err) {
        if (cancelled) return;
        // The server refused this account - wrong domain, or not on the
        // roster. Signing out is the only way forward, so make that the
        // offered action.
        setError(err.message);
        await signOut().catch(() => {});
      } finally {
        if (!cancelled) setBusy(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [firebaseUser]);

  const onLogout = useCallback(async () => {
    clearStaffSession();
    await signOut().catch(() => {});
    setSession(null);
    setPending(null);
    setRole(null);
    setError('');
  }, []);

  const onUserUpdate = (user) => setSession((s) => (s ? { ...s, user } : s));

  if (firebaseUser === undefined || busy || (restoring && !staffChecked && !session)) {
    return (
      <div className={styles.appContainer}>
        <div className={styles.authContainer}>
          <div className={styles.authCard}>
            <p className={styles.muted}>Signing you in…</p>
          </div>
        </div>
      </div>
    );
  }

  if (session) {
    return <Dashboard session={session} onLogout={onLogout} onUserUpdate={onUserUpdate} />;
  }

  if (pending) {
    return (
      <RegisterView
        email={pending.email}
        suggestedName={pending.name}
        onDone={(user) => {
          setSession({ user });
          setPending(null);
        }}
        onCancel={onLogout}
      />
    );
  }

  if (error && firebaseUser) {
    return (
      <div className={styles.appContainer}>
        <div className={styles.authContainer}>
          <div className={styles.authCard}>
            <ErrorBox text={error} />
            <button type="button" className={styles.dangerBtn} onClick={onLogout}>
              Sign out and try another account
            </button>
          </div>
        </div>
      </div>
    );
  }

  if (!configured) {
    return (
      <div className={styles.appContainer}>
        <div className={styles.authContainer}>
          <div className={styles.authCard}>
            <ErrorBox text="Sign-in is not set up for this site yet. Please use the Android app, or contact the department." />
            <p className={styles.muted}><Link href="/">Back to the main site</Link></p>
          </div>
        </div>
      </div>
    );
  }

  if (!role) return <RolePicker onPick={setRole} />;
  return (
    <SignInView
      role={role}
      error={error}
      onBack={() => { setRole(null); setError(''); }}
      onStaff={(res) => {
        setStaffSession(res.token, res.user);
        setSession({ user: res.user });
      }}
    />
  );
}

// ---------------------------------------------------------------------------
// Sign in
// ---------------------------------------------------------------------------

/// The first screen, the same three doors the app offers.
///
/// Picking one only decides which sign-in options appear next. It grants
/// nothing: what a person may actually do comes from the profile the server
/// returns once they have proved who they are.
function RolePicker({ onPick }) {
  const doors = [
    ['STUDENT', 'Student', 'Raise an OD, add your result and certificates.'],
    ['ADVISOR', 'Class Advisor', 'Review your class and recommend to the HOD.'],
    ['HOD', 'HOD', 'Sanction ODs and see the whole department.'],
  ];

  return (
    <div className={styles.appContainer}>
      <div className={styles.authContainer}>
        <div className={styles.authCard}>
          <div className={styles.authHead}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/college_logo.png" alt="SMVEC" className={styles.authLogo} />
            <h1 className={styles.authTitle}>SMVEC-IT OD Portal</h1>
            <p className={styles.authSubtitle}>Department of Information Technology</p>
          </div>

          <div className={styles.roleGrid}>
            {doors.map(([value, label, hint]) => (
              <button
                key={value}
                type="button"
                className={styles.roleCard}
                onClick={() => onPick(value)}
              >
                <span className={styles.roleCardTitle}>{label}</span>
                <span className={styles.roleCardHint}>{hint}</span>
              </button>
            ))}
          </div>

          <p className={styles.muted}>
            <Link href="/">Back to the main site</Link>
          </p>
        </div>
      </div>
    </div>
  );
}

function SignInView({ role, error, onBack, onStaff }) {
  const [busy, setBusy] = useState(false);
  const [localError, setLocalError] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  const isStudent = role === 'STUDENT';

  const google = async () => {
    setBusy(true);
    setLocalError('');
    try {
      await signInWithGoogle();
      // The auth listener in PortalPage takes over from here.
    } catch (err) {
      const message = describeAuthError(err);
      if (message) setLocalError(message);
      setBusy(false);
    }
  };

  const withPassword = async (ev) => {
    ev.preventDefault();
    setBusy(true);
    setLocalError('');
    try {
      const res = await apiPublic('PASSWORD_LOGIN', {
        email: email.trim().toLowerCase(),
        password,
      });
      onStaff(res);
    } catch (err) {
      setLocalError(err.message);
      setBusy(false);
    }
  };

  return (
    <div className={styles.appContainer}>
      <div className={styles.authContainer}>
        <div className={styles.authCard}>
          <div className={styles.authHead}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/college_logo.png" alt="SMVEC" className={styles.authLogo} />
            <h1 className={styles.authTitle}>
              {isStudent ? 'Student sign in' : role === 'HOD' ? 'HOD sign in' : 'Class advisor sign in'}
            </h1>
            <p className={styles.authSubtitle}>
              {isStudent
                ? `An OD is filed against your real college address, so Google is the only way in. Use your ${DOMAIN} account.`
                : `Use your college ${DOMAIN} account, or the password the department gave you.`}
            </p>
          </div>

          <button type="button" className={styles.primaryBtn} onClick={google} disabled={busy}>
            {busy ? 'Opening Google…' : 'Continue with Google'}
          </button>

          {!isStudent && (
            <>
              <p className={styles.muted}>or</p>
              <form className={styles.form} onSubmit={withPassword}>
                <Field label="Email">
                  <input
                    type="email"
                    className={styles.input}
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder={`name${DOMAIN}`}
                    required
                    autoComplete="username"
                  />
                </Field>
                <Field label="Password">
                  <input
                    type="password"
                    className={styles.input}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    autoComplete="current-password"
                  />
                </Field>
                <button type="submit" className={styles.secondaryBtn} disabled={busy}>
                  {busy ? 'Checking…' : 'Sign in with password'}
                </button>
              </form>
            </>
          )}

          {(localError || error) && <ErrorBox text={localError || error} />}

          <button type="button" className={styles.linkBtn} onClick={onBack}>
            ← Choose a different role
          </button>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// First-time profile
// ---------------------------------------------------------------------------

function RegisterView({ email, suggestedName, onDone, onCancel }) {
  const [form, setForm] = useState({
    name: suggestedName || '', rollNumber: '', year: '', section: '',
  });
  const [classes, setClasses] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const set = (k) => (ev) => setForm((f) => ({ ...f, [k]: ev.target.value }));

  // Students never pick an advisor: the class they are in decides it, and the
  // server derives it from the class rather than trusting anything sent here.
  const yearOptions = classes ? classes.map((c) => c.year) : YEARS;
  const sectionsFor = (year) => classes?.find((c) => String(c.year) === String(year))?.sections || [];
  const sectionOptions = classes ? sectionsFor(form.year).map((s) => s.section) : SECTIONS;
  const resolvedAdvisor = sectionsFor(form.year).find((s) => s.section === form.section) || null;
  const onYearChange = (ev) => setForm((f) => ({ ...f, year: ev.target.value, section: '' }));

  useEffect(() => {
    let cancelled = false;
    apiPublic('CLASSES')
      .then((res) => !cancelled && setClasses(res.classes || []))
      .catch(() => !cancelled && setClasses([]));
    return () => { cancelled = true; };
  }, []);

  const submit = async (ev) => {
    ev.preventDefault();
    setBusy(true);
    setError('');
    try {
      const res = await api('REGISTER', {
        name: form.name,
        registerNumber: form.rollNumber,
        year: form.year,
        section: form.section,
      });
      onDone(res.user);
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <div className={styles.appContainer}>
      <div className={styles.authContainer}>
        <div className={styles.authCard}>
          <div className={styles.authHead}>
            <h1 className={styles.authTitle}>Complete your profile</h1>
            <p className={styles.authSubtitle}>
              Signed in as <b>{email}</b>. We just need a few details the first time.
            </p>
          </div>

          <form className={styles.form} onSubmit={submit}>
            <Field label="Full name">
              <input className={styles.input} value={form.name} onChange={set('name')} required maxLength={80} />
            </Field>

            <Field label="Register number">
              <input className={styles.input} value={form.rollNumber} onChange={set('rollNumber')} required maxLength={30} />
            </Field>

            <Field label="Year" group>
              <select className={styles.input} value={form.year} onChange={onYearChange} required>
                <option value="">Select year</option>
                {yearOptions.map((y) => <option key={y} value={y}>{y}</option>)}
              </select>
            </Field>

            <Field label="Section" group>
              <select className={styles.input} value={form.section} onChange={set('section')} required disabled={!form.year}>
                <option value="">{form.year ? 'Select section' : 'Choose year first'}</option>
                {sectionOptions.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </Field>

            <Field label="Class advisor">
              <p className={styles.muted}>
                {classes === null
                  ? 'Loading classes…'
                  : resolvedAdvisor
                    ? resolvedAdvisor.advisorName
                    : 'Choose your year and section'}
              </p>
            </Field>

            {error && <ErrorBox text={error} />}

            <button type="submit" className={styles.primaryBtn} disabled={busy}>
              {busy ? 'Saving…' : 'Continue'}
            </button>
            <button type="button" className={styles.linkBtn} onClick={onCancel}>Sign out</button>
          </form>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// The shell
// ---------------------------------------------------------------------------

function Dashboard({ session, onLogout, onUserUpdate }) {
  const { user } = session;
  const [data, setData] = useState({ requests: [], notifications: [], auditLogs: [] });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showNotifs, setShowNotifs] = useState(false);
  const [toast, setToast] = useState('');
  const [tab, setTab] = useState('HOME');

  const call = useCallback(
    async (action, payload) => {
      try {
        return await api(action, payload);
      } catch (err) {
        if (err.status === 401) onLogout();
        throw err;
      }
    },
    [onLogout],
  );

  const refresh = useCallback(
    () => call('SYNC')
      .then((res) => {
        setData(res.data);
        setError('');
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false)),
    [call],
  );

  // Sync on load and when the tab regains focus. No background polling.
  useEffect(() => {
    refresh();
    const onVisible = () => document.visibilityState === 'visible' && refresh();
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [refresh]);

  useEffect(() => {
    if (!toast) return undefined;
    const t = setTimeout(() => setToast(''), 3500);
    return () => clearTimeout(t);
  }, [toast]);

  // Applies a server-updated request locally so we don't need another SYNC.
  const upsert = (request) => setData((d) => {
    const rest = d.requests.filter((r) => r.id !== request.id);
    return {
      ...d,
      requests: [request, ...rest]
        .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt))),
    };
  });

  const roleName = { STUDENT: 'Student portal', ADVISOR: 'Class advisor portal', HOD: 'HOD portal' }[user.role];
  const badgeClass = { STUDENT: styles.badgeStudent, ADVISOR: styles.badgeStaff, HOD: styles.badgeHod }[user.role];
  const ctx = { user, call, upsert, refresh, setToast, onUserUpdate, onLogout };

  const unread = data.notifications.filter((n) => !n.isRead).length;

  const markRead = async () => {
    setShowNotifs(true);
    if (unread === 0) return;
    try {
      await call('MARK_READ');
      setData((d) => ({
        ...d,
        notifications: d.notifications.map((n) => ({ ...n, isRead: true })),
      }));
    } catch {
      // Not worth troubling anyone over; the badge will clear on next sync.
    }
  };

  // The same tabs the app offers each role, in the same order.
  const tabs = {
    STUDENT: [['HOME', 'OD requests'], ['PREVIOUS', 'Previous'], ['REPORTS', 'Reports'], ['PROFILE', 'Profile']],
    ADVISOR: [['HOME', 'Dashboard'], ['REQUESTS', 'Requests'], ['STUDENTS', 'Students'], ['REPORTS', 'Reports'], ['PROFILE', 'Profile']],
    HOD: [['HOME', 'Dashboard'], ['REQUESTS', 'Requests'], ['STUDENTS', 'Students'], ['REPORTS', 'Reports'], ['AUDIT', 'Audit'], ['PROFILE', 'Profile']],
  }[user.role];

  return (
    <div className={styles.appContainer}>
      <TopBar subtitle={roleName}>
        <span className={`${styles.roleBadge} ${badgeClass}`}>
          {user.name}
          {user.role === 'STUDENT' && user.registerNumber ? ` · ${user.registerNumber}` : ''}
        </span>
        <button type="button" className={styles.iconBtn} onClick={markRead} aria-label="Notifications">
          🔔
          {unread > 0 && <span className={styles.notifBadge}>{unread}</span>}
        </button>
        <button type="button" className={styles.ghostBtn} onClick={refresh}>Refresh</button>
        <button type="button" className={styles.dangerBtn} onClick={onLogout}>Sign out</button>
      </TopBar>

      <main className={styles.main}>
        {error && <ErrorBox text={error} />}
        <Tabs value={tab} onChange={setTab} items={tabs} />
        {loading ? (
          <p className={styles.muted}>Loading…</p>
        ) : user.role === 'STUDENT' ? (
          <StudentView data={data} ctx={ctx} tab={tab} />
        ) : user.role === 'ADVISOR' ? (
          <AdvisorView data={data} ctx={ctx} tab={tab} />
        ) : (
          <HodView data={data} ctx={ctx} tab={tab} />
        )}
      </main>

      {showNotifs && (
        <Modal title="Notifications" onClose={() => setShowNotifs(false)}>
          {data.notifications.length === 0 ? (
            <p className={styles.muted}>No notifications yet.</p>
          ) : (
            <ul className={styles.notifList}>
              {data.notifications.map((n) => (
                <li key={n.id} className={styles.notifItem}>
                  <strong>{n.title}</strong>
                  <span>{n.text}</span>
                  <small>{fmtTime(n.time)}</small>
                </li>
              ))}
            </ul>
          )}
        </Modal>
      )}

      {toast && <div className={styles.toast}>{toast}</div>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Student
// ---------------------------------------------------------------------------

function StudentView({ data, ctx, tab }) {
  const { user } = ctx;
  const [showNew, setShowNew] = useState(false);
  const [editClass, setEditClass] = useState(false);
  const [resultFor, setResultFor] = useState(null);
  const [filesFor, setFilesFor] = useState(null);
  const reqs = data.requests;
  const count = (fn) => reqs.filter(fn).length;

  const open = reqs.filter((r) => r.status === 'PENDING_ADVISOR' || r.status === 'APPROVED_BY_ADVISOR');
  const closed = reqs.filter((r) => r.status === 'APPROVED' || String(r.status).startsWith('REJECTED'));
  const awaitingResult = reqs.filter((r) => r.status === 'APPROVED' && r.resultStatus === 'PENDING');

  const modals = (
    <>
      {showNew && <NewOdModal ctx={ctx} onClose={() => setShowNew(false)} />}
      {editClass && <ClassModal ctx={ctx} onClose={() => setEditClass(false)} />}
      {resultFor && (
        <ResultModal
          ctx={ctx}
          request={data.requests.find((r) => r.id === resultFor.id) || resultFor}
          onAttach={() => setFilesFor(resultFor)}
          onClose={() => setResultFor(null)}
        />
      )}
      {filesFor && (
        <AttachmentsModal
          ctx={ctx}
          request={data.requests.find((r) => r.id === filesFor.id) || filesFor}
          onClose={() => setFilesFor(null)}
        />
      )}
    </>
  );

  if (tab === 'REPORTS') {
    return <>{<ReportsView rows={reqs} scope="student" ctx={ctx} />}{modals}</>;
  }

  if (tab === 'PROFILE') {
    return (
      <>
        <ProfileView ctx={ctx} onEditClass={() => setEditClass(true)} />
        {modals}
      </>
    );
  }

  if (tab === 'PREVIOUS') {
    return (
      <>
        <h3 className={styles.sectionHeading}>Previous requests</h3>
        {closed.length === 0 ? (
          <Empty text="Nothing closed yet." />
        ) : (
          <div className={styles.list}>
            {closed.map((r) => (
              <RequestCard key={r.id} r={r} showStepper>
                {r.status === 'APPROVED' && r.resultStatus === 'PENDING' && (
                  <button className={styles.secondaryBtn} onClick={() => setResultFor(r)}>Add event result</button>
                )}
                {r.status === 'APPROVED' && (
                  <button className={styles.ghostBtn} onClick={() => setFilesFor(r)}>Attachments</button>
                )}
              </RequestCard>
            ))}
          </div>
        )}
        {modals}
      </>
    );
  }

  return (
    <>
      <section className={styles.banner}>
        <div>
          <h2 className={styles.bannerTitle}>Hello, {user.name}</h2>
          <p className={styles.bannerSub}>
            {user.registerNumber} · Year {user.year} · Section {user.section} · {user.department}
          </p>
        </div>
        <button type="button" className={styles.bannerBtn} onClick={() => setShowNew(true)}>+ New OD request</button>
      </section>

      <div className={styles.kpiGrid}>
        <Kpi label="Total" value={reqs.length} />
        <Kpi label="In review" value={open.length} />
        <Kpi label="Approved" value={count((r) => r.status === 'APPROVED')} />
        <Kpi label="Won" value={count((r) => r.resultStatus === 'WON')} />
      </div>

      {awaitingResult.length > 0 && (
        <>
          <h3 className={styles.sectionHeading}>Waiting for your result</h3>
          <div className={styles.list}>
            {awaitingResult.map((r) => (
              <RequestCard key={r.id} r={r}>
                <button className={styles.primaryBtn} onClick={() => setResultFor(r)}>Submit result</button>
                <button className={styles.ghostBtn} onClick={() => setFilesFor(r)}>Attach</button>
              </RequestCard>
            ))}
          </div>
        </>
      )}

      <h3 className={styles.sectionHeading}>Active requests</h3>
      {open.length === 0 ? (
        <Empty
          text="No requests are in review."
          action={<button className={styles.primaryBtn} onClick={() => setShowNew(true)}>Raise an OD</button>}
        />
      ) : (
        <div className={styles.list}>
          {open.map((r) => <RequestCard key={r.id} r={r} showStepper />)}
        </div>
      )}

      {modals}
    </>
  );
}

function NewOdModal({ ctx, onClose }) {
  const { user, call, upsert, setToast } = ctx;
  const [form, setForm] = useState(() => {
    const d = new Date(Date.now() + 3 * 864e5);
    return {
      submissionType: 'SOLO',
      eventType: 'Hackathon',
      eventName: '',
      eventDate: d.toISOString().slice(0, 10),
      dayCount: 1,
      description: '',
      teamMembers: [`${user.name} (${user.registerNumber || ''})`],
    };
  });
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value });
  const days = Math.min(Math.max(Number(form.dayCount) || 1, 1), 30);
  const lastDay = addDays(form.eventDate, days - 1);

  const submit = async (ev) => {
    ev.preventDefault();
    setError('');
    setBusy(true);
    try {
      const day = DAYS[new Date(`${form.eventDate}T00:00:00`).getDay()];
      const res = await call('CREATE_OD', {
        ...form,
        eventDay: day,
        dayCount: days,
        eventEndDate: lastDay,
        teamMembers: form.submissionType === 'TEAM' ? form.teamMembers : [],
      });
      upsert(res.request);
      setToast('OD request submitted.');
      onClose();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const setMember = (i, v) => setForm((f) => {
    const teamMembers = [...f.teamMembers];
    teamMembers[i] = v;
    return { ...f, teamMembers };
  });

  return (
    <Modal title="New OD request" onClose={onClose}>
      <form onSubmit={submit} className={styles.form}>
        <div className={styles.grid2}>
          <Field label="Event type" group>
            <select className={styles.input} value={form.eventType} onChange={set('eventType')} required>
              {EVENT_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
            </select>
          </Field>
          <Field label="Participation" group>
            <select className={styles.input} value={form.submissionType} onChange={set('submissionType')}>
              <option value="SOLO">Individual</option>
              <option value="TEAM">Team</option>
            </select>
          </Field>
        </div>

        <Field label="Event name">
          <input className={styles.input} value={form.eventName} onChange={set('eventName')} required maxLength={120} />
        </Field>

        <div className={styles.grid2}>
          <Field label="First day" group>
            <input type="date" className={styles.input} value={form.eventDate} onChange={set('eventDate')} required />
          </Field>
          <Field label="Number of days" group>
            <input type="number" min={1} max={30} className={styles.input} value={form.dayCount} onChange={set('dayCount')} required />
          </Field>
        </div>
        <Field label="Last day">
          {/* Derived, so the two cannot disagree. */}
          <p className={styles.muted}>{fmtDate(lastDay)}</p>
        </Field>

        <Field label="Description">
          <textarea className={styles.input} rows={3} value={form.description} onChange={set('description')} required maxLength={1000} />
        </Field>

        {form.submissionType === 'TEAM' && (
          <Field label="Team members">
            {form.teamMembers.map((m, i) => (
              <div key={i} className={styles.inputWrap}>
                <input
                  className={styles.input}
                  value={m}
                  onChange={(e) => setMember(i, e.target.value)}
                  placeholder="Name (Register number)"
                  maxLength={80}
                />
                {form.teamMembers.length > 1 && (
                  <button
                    type="button"
                    className={styles.inputAddon}
                    onClick={() => setForm((f) => ({
                      ...f, teamMembers: f.teamMembers.filter((_, j) => j !== i),
                    }))}
                  >
                    ✕
                  </button>
                )}
              </div>
            ))}
            {form.teamMembers.length < 5 && (
              <button
                type="button"
                className={styles.linkBtn}
                onClick={() => setForm((f) => ({ ...f, teamMembers: [...f.teamMembers, ''] }))}
              >
                + Add member
              </button>
            )}
          </Field>
        )}

        <ErrorBox text={error} />
        <button type="submit" className={styles.primaryBtn} disabled={busy}>
          {busy ? 'Submitting…' : 'Submit request'}
        </button>
      </form>
    </Modal>
  );
}

function ResultModal({ ctx, request, onAttach, onClose }) {
  const { call, upsert, setToast } = ctx;
  const [status, setStatus] = useState('PARTICIPATED');
  const [projectName, setProjectName] = useState(request.eventName);
  const [prize, setPrize] = useState('');
  const [prizeDetails, setPrizeDetails] = useState('');
  const [description, setDescription] = useState('');
  const [contributions, setContributions] = useState(() => Object.fromEntries(
    (request.team || []).map((m) => [m.id, m.contribution || '']),
  ));
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const have = new Set((request.files || []).map((f) => f.kind));
  const missing = evidenceFor(status).filter((k) => !have.has(k));

  const submit = async (ev) => {
    ev.preventDefault();
    setBusy(true);
    setError('');
    try {
      const res = await call('SUBMIT_RESULT', {
        reqId: request.id,
        status,
        projectName,
        description,
        // Only meaningful for a win, and the server insists on it there.
        prize: status === 'WON' ? prize : '',
        prizeDetails: status === 'WON' ? prizeDetails : '',
        teamContributions: (request.team || []).map((m) => ({
          id: m.id,
          contribution: contributions[m.id] || '',
        })),
      });
      upsert(res.request);
      setToast('Result saved.');
      onClose();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title={`Result · ${request.eventName}`} onClose={onClose}>
      <form onSubmit={submit} className={styles.form}>
        <Field label="Outcome" group>
          <div className={styles.segmented}>
            {[['PARTICIPATED', 'Participated'], ['WON', 'Won a prize']].map(([v, l]) => (
              <button key={v} type="button" className={status === v ? styles.segActive : ''} onClick={() => setStatus(v)}>
                {l}
              </button>
            ))}
          </div>
        </Field>

        <Field label="Project / topic name">
          <input className={styles.input} value={projectName} onChange={(e) => setProjectName(e.target.value)} maxLength={120} />
        </Field>

        {status === 'WON' && (
          <>
            <Field label="Prize">
              <input
                className={styles.input}
                value={prize}
                onChange={(e) => setPrize(e.target.value)}
                required
                maxLength={80}
                placeholder="First place, Runner-up, Best paper…"
              />
            </Field>
            <Field label="Prize details">
              <input
                className={styles.input}
                value={prizeDetails}
                onChange={(e) => setPrizeDetails(e.target.value)}
                maxLength={300}
                placeholder="Cash award, certificate, trophy…"
              />
            </Field>
          </>
        )}

        <Field label="Details">
          <textarea className={styles.input} rows={3} value={description} onChange={(e) => setDescription(e.target.value)} maxLength={1000} />
        </Field>

        {request.submissionType === 'TEAM' && (request.team || []).length > 0 && (
          <>
            <p className={styles.muted}>
              The department credits people, not entries. Say what each member contributed.
            </p>
            {(request.team || []).map((m) => (
              <Field key={m.id} label={m.name}>
                <textarea
                  className={styles.input}
                  rows={2}
                  value={contributions[m.id] || ''}
                  onChange={(e) => setContributions((c) => ({ ...c, [m.id]: e.target.value }))}
                  maxLength={400}
                  required
                  placeholder="Built the backend, presented the paper…"
                />
              </Field>
            ))}
          </>
        )}

        <Field label="Evidence">
          <ul className={styles.evidenceList}>
            {evidenceFor(status).map((kind) => {
              const done = have.has(kind);
              return (
                <li key={kind} className={done ? styles.evidenceDone : styles.evidenceTodo}>
                  {done ? '✓' : '○'} {kindLabel(kind)}
                </li>
              );
            })}
          </ul>
          {missing.length > 0 && (
            <button type="button" className={styles.secondaryBtn} onClick={onAttach}>
              Attach {missing.length === 1 ? 'the missing file' : `${missing.length} missing files`}
            </button>
          )}
        </Field>

        <ErrorBox text={error} />
        <button type="submit" className={styles.primaryBtn} disabled={busy || missing.length > 0}>
          {busy ? 'Saving…' : missing.length > 0 ? 'Attach the evidence first' : 'Save result'}
        </button>
      </form>
    </Modal>
  );
}

/// Adding and removing a request's attachments.
///
/// Images are shrunk in the browser before they are sent, the same way the
/// Android app does it, so a laptop full of twelve-megabyte phone photos does
/// not have to upload them whole.
function AttachmentsModal({ ctx, request, onClose }) {
  const { call, upsert, setToast } = ctx;
  const [busyKind, setBusyKind] = useState(null);
  const [step, setStep] = useState('');
  const [error, setError] = useState('');

  const files = request.files || [];

  const refreshRequest = async () => {
    const res = await call('SYNC');
    const fresh = (res.data?.requests || []).find((r) => r.id === request.id);
    if (fresh) upsert(fresh);
  };

  const onPick = async (kind, file) => {
    if (!file) return;
    setBusyKind(kind);
    setError('');
    try {
      await uploadFile({ requestId: request.id, kind, file, onStep: setStep });
      await refreshRequest();
      setToast('Attached.');
    } catch (err) {
      setError(err.message);
    } finally {
      setBusyKind(null);
      setStep('');
    }
  };

  const remove = async (file) => {
    if (!window.confirm(`Remove ${kindLabel(file.kind)}? This cannot be undone.`)) return;
    setError('');
    try {
      await deleteFile(file.id);
      await refreshRequest();
      setToast('Removed.');
    } catch (err) {
      setError(err.message);
    }
  };

  return (
    <Modal title={`Attachments · ${request.eventName}`} onClose={onClose}>
      <p className={styles.muted}>
        Images are shrunk here before they are sent. Nothing is stored publicly:
        opening a file mints a link that lasts five minutes.
      </p>

      {FILE_KINDS.map(({ kind, label }) => {
        const mine = files.filter((f) => f.kind === kind);
        return (
          <div key={kind} className={styles.attachRow}>
            <div className={styles.attachHead}>
              <span className={styles.attachLabel}>
                {label}
                {kind === 'SUPPORTING_DOCUMENT' && <em> (optional)</em>}
              </span>
              <label className={styles.attachAdd}>
                {busyKind === kind ? (step || 'Working…') : 'Add'}
                <input
                  type="file"
                  accept="image/jpeg,image/png,image/webp,application/pdf"
                  hidden
                  disabled={busyKind !== null}
                  onChange={(e) => {
                    const file = e.target.files?.[0];
                    e.target.value = '';
                    onPick(kind, file);
                  }}
                />
              </label>
            </div>
            {mine.length === 0 ? (
              <p className={styles.muted}>Nothing attached.</p>
            ) : (
              <ul className={styles.attachList}>
                {mine.map((f) => (
                  <li key={f.id}>
                    <FileLink file={f} />
                    <span className={styles.muted}>{humanSize(f.sizeBytes)}</span>
                    <button type="button" className={styles.linkBtn} onClick={() => remove(f)}>Remove</button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        );
      })}

      <ErrorBox text={error} />
      <button type="button" className={styles.primaryBtn} onClick={onClose}>Done</button>
    </Modal>
  );
}

function ClassModal({ ctx, onClose }) {
  const { user, call, onUserUpdate, setToast } = ctx;
  const [form, setForm] = useState({ year: String(user.year || ''), section: user.section || '' });
  const [classes, setClasses] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    apiPublic('CLASSES')
      .then((res) => !cancelled && setClasses(res.classes || []))
      .catch(() => !cancelled && setClasses([]));
    return () => { cancelled = true; };
  }, []);

  const sectionsFor = (year) => classes?.find((c) => String(c.year) === String(year))?.sections || [];
  const yearOptions = classes ? classes.map((c) => c.year) : YEARS;
  const sectionOptions = classes ? sectionsFor(form.year).map((s) => s.section) : SECTIONS;
  const advisor = sectionsFor(form.year).find((s) => s.section === form.section) || null;

  const submit = async (ev) => {
    ev.preventDefault();
    setBusy(true);
    setError('');
    try {
      const res = await call('CHANGE_CLASS', { year: Number(form.year), section: form.section });
      onUserUpdate(res.user);
      setToast('Your class has been updated.');
      onClose();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title="Correct your class" onClose={onClose}>
      <form onSubmit={submit} className={styles.form}>
        <p className={styles.muted}>
          Your class decides which advisor reviews your requests. Requests you
          have already filed stay with the advisor who received them.
        </p>
        <div className={styles.grid2}>
          <Field label="Year">
            <select className={styles.input} value={form.year} onChange={(e) => setForm({ year: e.target.value, section: '' })} required>
              <option value="">Select year</option>
              {yearOptions.map((y) => <option key={y} value={y}>Year {y}</option>)}
            </select>
          </Field>
          <Field label="Section">
            <select className={styles.input} value={form.section} onChange={(e) => setForm({ ...form, section: e.target.value })} required disabled={!form.year}>
              <option value="">{form.year ? 'Select section' : 'Choose year first'}</option>
              {sectionOptions.map((s) => <option key={s} value={s}>Sec {s}</option>)}
            </select>
          </Field>
        </div>
        <Field label="Class advisor">
          <p className={styles.muted}>
            {classes === null ? 'Loading classes…' : advisor ? advisor.advisorName : 'Choose your year and section'}
          </p>
        </Field>
        <ErrorBox text={error} />
        <button type="submit" className={styles.primaryBtn} disabled={busy || !advisor}>
          {busy ? 'Saving…' : 'Save'}
        </button>
      </form>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
// Class advisor
// ---------------------------------------------------------------------------

function AdvisorView({ data, ctx, tab }) {
  const { user } = ctx;
  const [deciding, setDeciding] = useState(null);
  const [filter, setFilter] = useState('PENDING');
  const pending = data.requests.filter((r) => r.status === 'PENDING_ADVISOR');
  const reviewed = data.requests.filter((r) => r.status !== 'PENDING_ADVISOR');

  if (tab === 'REPORTS') return <ReportsView rows={data.requests} scope="advisor" ctx={ctx} />;
  if (tab === 'STUDENTS') return <StudentsView rows={data.requests} ctx={ctx} />;
  if (tab === 'PROFILE') return <ProfileView ctx={ctx} />;

  if (tab === 'REQUESTS') {
    const shown = filter === 'PENDING' ? pending : reviewed;
    return (
      <>
        <Tabs
          value={filter}
          onChange={setFilter}
          items={[['PENDING', `Pending (${pending.length})`], ['REVIEWED', `Reviewed (${reviewed.length})`]]}
        />
        {shown.length === 0 ? (
          <Empty text={filter === 'PENDING' ? 'No requests waiting for your review.' : 'Nothing reviewed yet.'} />
        ) : (
          <div className={styles.list}>
            {shown.map((r) => (
              <RequestCard key={r.id} r={r} showStudent>
                {r.status === 'PENDING_ADVISOR' && (
                  <>
                    <button className={styles.approveBtn} onClick={() => setDeciding({ r, approve: true })}>Approve and forward</button>
                    <button className={styles.rejectBtn} onClick={() => setDeciding({ r, approve: false })}>Reject</button>
                  </>
                )}
              </RequestCard>
            ))}
          </div>
        )}
        {deciding && <DecisionModal ctx={ctx} action="ADVISOR_DECIDE" {...deciding} onClose={() => setDeciding(null)} />}
      </>
    );
  }

  return (
    <>
      <section className={styles.banner}>
        <div>
          <h2 className={styles.bannerTitle}>{user.name}</h2>
          <p className={styles.bannerSub}>
            {/* Assigned by the department, so it is shown rather than edited. */}
            Class advisor ·{' '}
            {(user.classes || []).length
              ? (user.classes || []).map((c) => `Year ${c.year} Section ${c.section}`).join(', ')
              : 'No class assigned yet'}
          </p>
        </div>
      </section>

      <div className={styles.kpiGrid}>
        <Kpi label="Awaiting review" value={pending.length} />
        <Kpi label="Forwarded to HOD" value={data.requests.filter((r) => r.status === 'APPROVED_BY_ADVISOR').length} />
        <Kpi label="Approved" value={data.requests.filter((r) => r.status === 'APPROVED').length} />
        <Kpi label="Prizes won" value={data.requests.filter((r) => r.resultStatus === 'WON').length} />
      </div>

      <h3 className={styles.sectionHeading}>Waiting for your review</h3>
      {pending.length === 0 ? (
        <Empty text="Nothing is waiting for you." />
      ) : (
        <div className={styles.list}>
          {pending.slice(0, 5).map((r) => (
            <RequestCard key={r.id} r={r} showStudent>
              <button className={styles.approveBtn} onClick={() => setDeciding({ r, approve: true })}>Approve and forward</button>
              <button className={styles.rejectBtn} onClick={() => setDeciding({ r, approve: false })}>Reject</button>
            </RequestCard>
          ))}
        </div>
      )}
      {deciding && <DecisionModal ctx={ctx} action="ADVISOR_DECIDE" {...deciding} onClose={() => setDeciding(null)} />}
    </>
  );
}

// ---------------------------------------------------------------------------
// HOD
// ---------------------------------------------------------------------------

function HodView({ data, ctx, tab }) {
  const [deciding, setDeciding] = useState(null);
  const [filter, setFilter] = useState('AWAITING');
  const [query, setQuery] = useState('');
  const reqs = data.requests;
  const awaiting = reqs.filter((r) => r.status === 'APPROVED_BY_ADVISOR');

  const shown = useMemo(() => {
    const base = filter === 'AWAITING' ? awaiting : reqs;
    const q = query.trim().toLowerCase();
    if (!q) return base;
    return base.filter((r) => [r.studentName, r.registerNumber, r.eventName, r.advisorName, r.referenceNo, r.eventType]
      .some((v) => String(v || '').toLowerCase().includes(q)));
  }, [filter, reqs, awaiting, query]);

  if (tab === 'REPORTS') return <ReportsView rows={reqs} scope="hod" ctx={ctx} />;
  if (tab === 'STUDENTS') return <StudentsView rows={reqs} ctx={ctx} />;
  if (tab === 'PROFILE') return <ProfileView ctx={ctx} />;

  if (tab === 'AUDIT') {
    return data.auditLogs.length === 0 ? (
      <Empty text="No activity yet." />
    ) : (
      <div className={styles.tableWrap}>
        <table className={styles.table}>
          <thead>
            <tr><th>Time</th><th>What happened</th><th>By</th></tr>
          </thead>
          <tbody>
            {data.auditLogs.map((a) => (
              <tr key={a.id + a.time}>
                <td>{fmtTime(a.time)}</td>
                {/* The sentence the server composed, where the event name and
                    the person's name were both to hand. */}
                <td>{a.summary || a.action.replace(/_/g, ' ').toLowerCase()}</td>
                <td>{a.actorName || a.actor}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    );
  }

  if (tab === 'REQUESTS') {
    return (
      <>
        <div className={styles.rowBetween}>
          <Tabs
            value={filter}
            onChange={setFilter}
            items={[['AWAITING', `Awaiting (${awaiting.length})`], ['ALL', `All (${reqs.length})`]]}
          />
          <input
            className={`${styles.input} ${styles.search}`}
            placeholder="Search student, event, advisor…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        {shown.length === 0 ? (
          <Empty text={filter === 'AWAITING' ? 'Nothing waiting for your sanction.' : 'No requests found.'} />
        ) : (
          <div className={styles.list}>
            {shown.map((r) => (
              <RequestCard key={r.id} r={r} showStudent showAdvisor>
                {r.status === 'APPROVED_BY_ADVISOR' && (
                  <>
                    <button className={styles.approveBtn} onClick={() => setDeciding({ r, approve: true })}>Sanction OD</button>
                    <button className={styles.rejectBtn} onClick={() => setDeciding({ r, approve: false })}>Reject</button>
                  </>
                )}
              </RequestCard>
            ))}
          </div>
        )}
        {deciding && <DecisionModal ctx={ctx} action="HOD_DECIDE" {...deciding} onClose={() => setDeciding(null)} />}
      </>
    );
  }

  return (
    <>
      <section className={styles.banner}>
        <div>
          <h2 className={styles.bannerTitle}>HOD dashboard</h2>
          <p className={styles.bannerSub}>Department of Information Technology · Final OD sanction</p>
        </div>
      </section>

      <div className={styles.kpiGrid}>
        <Kpi label="Awaiting sanction" value={awaiting.length} />
        <Kpi label="With advisors" value={reqs.filter((r) => r.status === 'PENDING_ADVISOR').length} />
        <Kpi label="Approved" value={reqs.filter((r) => r.status === 'APPROVED').length} />
        <Kpi label="Prizes won" value={reqs.filter((r) => r.resultStatus === 'WON').length} />
      </div>

      <h3 className={styles.sectionHeading}>Waiting for your sanction</h3>
      {awaiting.length === 0 ? (
        <Empty text="Nothing is waiting for you." />
      ) : (
        <div className={styles.list}>
          {awaiting.slice(0, 5).map((r) => (
            <RequestCard key={r.id} r={r} showStudent showAdvisor>
              <button className={styles.approveBtn} onClick={() => setDeciding({ r, approve: true })}>Sanction OD</button>
              <button className={styles.rejectBtn} onClick={() => setDeciding({ r, approve: false })}>Reject</button>
            </RequestCard>
          ))}
        </div>
      )}
      {deciding && <DecisionModal ctx={ctx} action="HOD_DECIDE" {...deciding} onClose={() => setDeciding(null)} />}
    </>
  );
}

function DecisionModal({ ctx, action, r, approve, onClose }) {
  const { call, upsert, setToast } = ctx;
  const [remarks, setRemarks] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (ev) => {
    ev.preventDefault();
    setBusy(true);
    setError('');
    try {
      const res = await call(action, { reqId: r.id, approve, remarks });
      upsert(res.request);
      setToast(approve ? 'Approved.' : 'Rejected.');
      onClose();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title={approve ? 'Approve this OD?' : 'Reject this OD?'} onClose={onClose}>
      <form onSubmit={submit} className={styles.form}>
        <p className={styles.muted}>
          {r.studentName} · {r.eventName} · {fmtRange(r)}
        </p>
        <Field label="Remarks (optional)">
          <textarea
            className={styles.input}
            rows={3}
            value={remarks}
            onChange={(e) => setRemarks(e.target.value)}
            maxLength={500}
            placeholder="Shown to the student with your decision"
          />
        </Field>
        <ErrorBox text={error} />
        <button type="submit" className={approve ? styles.approveBtn : styles.rejectBtn} disabled={busy}>
          {busy ? 'Saving…' : approve ? 'Approve' : 'Reject'}
        </button>
      </form>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
// Students
// ---------------------------------------------------------------------------

/// The department's students, rolled up from the requests the caller can see.
/// There is no separate students action: an advisor's list is their class and
/// the HOD's is everyone, which is already what SYNC returned.
function StudentsView({ rows, ctx }) {
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(null);

  const students = useMemo(() => {
    const map = new Map();
    for (const r of rows) {
      const key = r.registerNumber || r.studentEmail;
      if (!map.has(key)) {
        map.set(key, {
          key,
          name: r.studentName,
          registerNumber: r.registerNumber,
          year: r.year,
          section: r.section,
          advisorName: r.advisorName,
          requests: [],
        });
      }
      map.get(key).requests.push(r);
    }
    const list = [...map.values()];
    const q = query.trim().toLowerCase();
    return (q
      ? list.filter((s) => `${s.name} ${s.registerNumber}`.toLowerCase().includes(q))
      : list
    ).sort((a, b) => a.name.localeCompare(b.name));
  }, [rows, query]);

  if (open) {
    const student = students.find((s) => s.key === open);
    if (student) {
      return (
        <>
          <button type="button" className={styles.linkBtn} onClick={() => setOpen(null)}>← All students</button>
          <section className={styles.banner}>
            <div>
              <h2 className={styles.bannerTitle}>{student.name}</h2>
              <p className={styles.bannerSub}>
                {student.registerNumber} · Year {student.year} · Section {student.section}
                {' · '}Advisor: {student.advisorName}
              </p>
            </div>
          </section>
          <div className={styles.kpiGrid}>
            <Kpi label="Total ODs" value={student.requests.length} />
            <Kpi label="Approved" value={student.requests.filter((r) => r.status === 'APPROVED').length} />
            <Kpi label="Won" value={student.requests.filter((r) => r.resultStatus === 'WON').length} />
            <Kpi label="Participated" value={student.requests.filter((r) => r.resultStatus === 'PARTICIPATED').length} />
          </div>
          <div className={styles.list}>
            {student.requests.map((r) => <RequestCard key={r.id} r={r} showStepper />)}
          </div>
        </>
      );
    }
  }

  return (
    <>
      <div className={styles.rowBetween}>
        <h3 className={styles.sectionHeading}>{students.length} student{students.length === 1 ? '' : 's'}</h3>
        <input
          className={`${styles.input} ${styles.search}`}
          placeholder="Search name or register number"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
      </div>
      {students.length === 0 ? (
        <Empty text="No students yet." />
      ) : (
        <div className={styles.tableWrap}>
          <table className={styles.table}>
            <thead>
              <tr><th>Student</th><th>Register no.</th><th>Class</th><th>ODs</th><th>Won</th><th /></tr>
            </thead>
            <tbody>
              {students.map((s) => (
                <tr key={s.key}>
                  <td>{s.name}</td>
                  <td>{s.registerNumber}</td>
                  <td>Year {s.year} · {s.section}</td>
                  <td>{s.requests.length}</td>
                  <td>{s.requests.filter((r) => r.resultStatus === 'WON').length}</td>
                  <td>
                    <button type="button" className={styles.linkBtn} onClick={() => setOpen(s.key)}>Open</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

/// Search, filters, one record in full, and the three exports.
///
/// The rows are whatever the server already returned, so a student sees their
/// own, an advisor their class and the HOD the department - the scoping is not
/// re-decided here.
function ReportsView({ rows, scope, ctx }) {
  const [query, setQuery] = useState('');
  const [year, setYear] = useState('');
  const [section, setSection] = useState('');
  const [eventType, setEventType] = useState('');
  const [status, setStatus] = useState('');
  const [result, setResult] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [openId, setOpenId] = useState(null);
  const [exporting, setExporting] = useState('');

  const hasFilters = Boolean(query || year || section || eventType || status || result || from || to);

  const filters = {
    ...(year ? { Year: year } : {}),
    ...(section ? { Section: section } : {}),
    ...(eventType ? { 'Event type': eventType } : {}),
    ...(status ? { Status: status } : {}),
    ...(result ? { Result: result } : {}),
    ...(from || to ? { 'Date range': `${from || '…'} to ${to || '…'}` } : {}),
    ...(query ? { Search: query } : {}),
  };

  const filtered = useMemo(() => rows.filter((r) => {
    if (year && String(r.year) !== year) return false;
    if (section && r.section !== section) return false;
    if (eventType && r.eventType !== eventType) return false;
    if (status === 'Approved' && r.status !== 'APPROVED') return false;
    if (status === 'Pending' && (r.status === 'APPROVED' || String(r.status).startsWith('REJECTED'))) return false;
    if (status === 'Rejected' && !String(r.status).startsWith('REJECTED')) return false;
    if (result === 'Won' && r.resultStatus !== 'WON') return false;
    if (result === 'Participated' && r.resultStatus !== 'PARTICIPATED') return false;
    if (result === 'No result' && r.resultStatus !== 'PENDING') return false;
    if (from && r.eventDate < from) return false;
    if (to && r.eventDate > to) return false;
    if (query) {
      const q = query.trim().toLowerCase();
      const hay = [r.studentName, r.registerNumber, r.eventName, r.resultProjectName,
        r.resultPrize, r.advisorName, r.eventType].join(' ').toLowerCase();
      if (!hay.includes(q)) return false;
    }
    return true;
  }), [rows, query, year, section, eventType, status, result, from, to]);

  const clear = () => {
    setQuery(''); setYear(''); setSection(''); setEventType('');
    setStatus(''); setResult(''); setFrom(''); setTo('');
  };

  const title = { hod: 'Department OD Report', advisor: 'Class OD Report', student: 'My OD Report' }[scope];

  /// Exports what is on screen. With nothing filtered that is everything the
  /// caller is allowed to see, which the server already decided.
  const runExport = async (format, only = null) => {
    const chosen = only ? [only] : filtered;
    if (chosen.length === 0) {
      ctx.setToast(hasFilters ? 'Nothing matches these filters.' : 'There is nothing to export yet.');
      return;
    }
    setExporting('Collecting photographs…');
    try {
      const records = await gather(chosen, {
        // Excel cannot embed images, so there is no point downloading them.
        withPhotos: format !== 'excel',
        onProgress: (done, total) => {
          if (total > 1) setExporting(`Preparing ${done} of ${total}…`);
        },
      });
      setExporting('Building the document…');
      await EXPORTERS[format]({
        records,
        title: only ? `${only.studentName} - ${only.eventName}` : title,
        filters: only ? {} : filters,
      });
      ctx.setToast('Report downloaded.');
    } catch (err) {
      ctx.setToast(`Export failed: ${err.message}`);
    } finally {
      setExporting('');
    }
  };

  const open = openId ? rows.find((r) => r.id === openId) : null;
  if (open) {
    return (
      <ReportDetail
        r={open}
        exporting={exporting}
        onExport={(format) => runExport(format, open)}
        onBack={() => setOpenId(null)}
      />
    );
  }

  const years = [...new Set(rows.map((r) => r.year))].sort();
  const sections = [...new Set(rows.map((r) => r.section))].sort();

  return (
    <>
      <input
        className={`${styles.input} ${styles.search}`}
        placeholder={scope === 'student'
          ? 'Search event, project, prize'
          : 'Search student, register no., event, project, prize'}
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />

      <div className={styles.filterRow}>
        {scope !== 'student' && (
          <>
            <select className={styles.input} value={year} onChange={(e) => setYear(e.target.value)}>
              <option value="">All years</option>
              {years.map((y) => <option key={y} value={y}>Year {y}</option>)}
            </select>
            <select className={styles.input} value={section} onChange={(e) => setSection(e.target.value)}>
              <option value="">All sections</option>
              {sections.map((s) => <option key={s} value={s}>Section {s}</option>)}
            </select>
          </>
        )}
        <select className={styles.input} value={eventType} onChange={(e) => setEventType(e.target.value)}>
          <option value="">All event types</option>
          {EVENT_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
        </select>
        <select className={styles.input} value={status} onChange={(e) => setStatus(e.target.value)}>
          <option value="">Any status</option>
          {['Approved', 'Pending', 'Rejected'].map((s) => <option key={s} value={s}>{s}</option>)}
        </select>
        <select className={styles.input} value={result} onChange={(e) => setResult(e.target.value)}>
          <option value="">Any result</option>
          {['Won', 'Participated', 'No result'].map((s) => <option key={s} value={s}>{s}</option>)}
        </select>
        <input type="date" className={styles.input} value={from} onChange={(e) => setFrom(e.target.value)} aria-label="From" />
        <input type="date" className={styles.input} value={to} onChange={(e) => setTo(e.target.value)} aria-label="To" />
        {hasFilters && (
          <button type="button" className={styles.linkBtn} onClick={clear}>Clear</button>
        )}
      </div>

      <div className={styles.rowBetween}>
        <span className={styles.sectionHeading}>
          {filtered.length} record{filtered.length === 1 ? '' : 's'}{hasFilters ? ' (filtered)' : ''}
        </span>
        {exporting ? (
          <span className={styles.muted}>{exporting}</span>
        ) : (
          <ExportMenu
            label={hasFilters ? 'Export filtered' : 'Export all'}
            onSelect={(format) => runExport(format)}
          />
        )}
      </div>

      {filtered.length === 0 ? (
        <Empty
          text={hasFilters ? 'Nothing matches these filters.' : 'Reports fill in as OD requests are raised.'}
          action={hasFilters ? <button className={styles.linkBtn} onClick={clear}>Clear filters</button> : null}
        />
      ) : (
        <div className={styles.tableWrap}>
          <table className={styles.table}>
            <thead>
              <tr>
                {scope !== 'student' && <th>Student</th>}
                <th>Event</th><th>Dates</th><th>Project</th><th>Result</th><th />
              </tr>
            </thead>
            <tbody>
              {filtered.map((r) => (
                <tr key={r.id} className={styles.clickableRow} onClick={() => setOpenId(r.id)}>
                  {scope !== 'student' && <td>{r.studentName}<br /><small className={styles.muted}>{r.registerNumber}</small></td>}
                  <td>{r.eventName}<br /><small className={styles.muted}>{r.eventType}</small></td>
                  <td>{fmtRange(r)}</td>
                  <td>{r.resultProjectName || '—'}</td>
                  <td>
                    {r.resultStatus === 'WON'
                      ? `🏆 ${r.resultPrize || 'Won'}`
                      : r.resultStatus === 'PARTICIPATED' ? 'Participated' : '—'}
                  </td>
                  <td><span className={styles.linkBtn}>Open</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}

/// One OD in full, and the place to export that record on its own - which is
/// what someone needs when they are sending one student's achievement rather
/// than a department listing.
function ReportDetail({ r, exporting, onExport, onBack }) {
  const images = (r.files || []).filter((f) => String(f.mimeType || '').startsWith('image/'));
  const documents = (r.files || []).filter((f) => !String(f.mimeType || '').startsWith('image/'));

  return (
    <>
      <div className={styles.rowBetween}>
        <button type="button" className={styles.linkBtn} onClick={onBack}>← Back to reports</button>
        {exporting ? <span className={styles.muted}>{exporting}</span> : <ExportMenu label="Export as" onSelect={onExport} />}
      </div>

      <section className={styles.banner}>
        <div>
          <h2 className={styles.bannerTitle}>{r.studentName}</h2>
          <p className={styles.bannerSub}>
            {r.registerNumber} · Year {r.year} · Section {r.section}
          </p>
        </div>
        <span className={`${styles.status} ${styles[`status_${(STATUS[r.status] || {}).tone || 'pending'}`]}`}>
          {r.resultStatus === 'WON' ? `Won · ${r.resultPrize || ''}`
            : r.resultStatus === 'PARTICIPATED' ? 'Participated' : 'Result not submitted'}
        </span>
      </section>

      <dl className={styles.detailGrid}>
        <div><dt>Event</dt><dd>{r.eventName}</dd></div>
        <div><dt>Type</dt><dd>{r.eventType}</dd></div>
        <div><dt>Dates</dt><dd>{fmtRange(r)}</dd></div>
        <div><dt>Duration</dt><dd>{r.dayCount === 1 ? '1 day' : `${r.dayCount || 1} days`}</dd></div>
        <div><dt>Participation</dt><dd>{r.submissionType === 'TEAM' ? `Team of ${(r.teamMembers || []).length}` : 'Individual'}</dd></div>
        <div><dt>Reference</dt><dd>{r.referenceNo}</dd></div>
        <div><dt>Project</dt><dd>{r.resultProjectName || r.eventName}</dd></div>
        {r.resultPrizeDetails && <div><dt>Prize details</dt><dd>{r.resultPrizeDetails}</dd></div>}
      </dl>

      <h3 className={styles.sectionHeading}>Description</h3>
      <p className={styles.desc}>{r.resultDescription || r.description}</p>

      {r.submissionType === 'TEAM' && (
        <>
          <h3 className={styles.sectionHeading}>Team and contribution</h3>
          {(r.team || []).length === 0 ? (
            <p className={styles.desc}>{(r.teamMembers || []).join(', ')}</p>
          ) : (
            <div className={styles.tableWrap}>
              <table className={styles.table}>
                <thead><tr><th>Member</th><th>What they contributed</th></tr></thead>
                <tbody>
                  {r.team.map((m) => (
                    <tr key={m.id}>
                      <td>{m.name}{m.registerNumber ? <><br /><small className={styles.muted}>{m.registerNumber}</small></> : null}</td>
                      <td className={m.contribution ? '' : styles.muted}>
                        {m.contribution || 'Contribution not recorded yet.'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}

      {images.length > 0 && (
        <>
          <h3 className={styles.sectionHeading}>Photographs</h3>
          <div className={styles.photoStrip}>
            {images.map((f) => <PhotoTile key={f.id} file={f} />)}
          </div>
        </>
      )}

      {documents.length > 0 && (
        <>
          <h3 className={styles.sectionHeading}>Documents</h3>
          <div className={styles.attachments}>
            {documents.map((f) => <FileLink key={f.id} file={f} />)}
          </div>
        </>
      )}

      {(r.files || []).length === 0 && <Empty text="Nothing has been attached to this OD." />}
    </>
  );
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

function ProfileView({ ctx, onEditClass }) {
  const { user, onLogout } = ctx;
  const isStudent = user.role === 'STUDENT';

  return (
    <>
      <section className={styles.banner}>
        <div>
          <h2 className={styles.bannerTitle}>{user.name}</h2>
          <p className={styles.bannerSub}>{user.email}</p>
        </div>
      </section>

      <dl className={styles.detailGrid}>
        <div><dt>Role</dt><dd>{{ STUDENT: 'Student', ADVISOR: 'Class advisor', HOD: 'Head of Department' }[user.role]}</dd></div>
        <div><dt>Department</dt><dd>{user.department}</dd></div>
        {isStudent && <div><dt>Register number</dt><dd>{user.registerNumber}</dd></div>}
        {isStudent && <div><dt>Class</dt><dd>Year {user.year} · Section {user.section}</dd></div>}
        {isStudent && <div><dt>Class advisor</dt><dd>{user.advisorName || 'Not set'}</dd></div>}
        {!isStudent && (
          <div>
            <dt>Classes</dt>
            <dd>
              {(user.classes || []).length
                ? user.classes.map((c) => `Year ${c.year} Section ${c.section}`).join(', ')
                : 'Assigned by the department'}
            </dd>
          </div>
        )}
      </dl>

      <div className={styles.actions}>
        {isStudent && onEditClass && (
          <button type="button" className={styles.secondaryBtn} onClick={onEditClass}>
            Registered under the wrong class?
          </button>
        )}
        <button type="button" className={styles.dangerBtn} onClick={onLogout}>Sign out</button>
      </div>
    </>
  );
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

function RequestCard({ r, showStudent, showAdvisor, showStepper, children }) {
  const st = STATUS[r.status] || { label: r.status, tone: 'pending' };
  return (
    <article className={styles.card}>
      <header className={styles.cardHeader}>
        <div>
          <div className={styles.metaRow}>
            <span className={styles.chip}>{r.eventType}</span>
            <span className={styles.chip}>{r.submissionType === 'TEAM' ? 'Team' : 'Solo'}</span>
            <span className={styles.idText}>{r.referenceNo}</span>
          </div>
          <h4 className={styles.cardEvent}>{r.eventName}</h4>
          <p className={styles.muted}>
            {fmtRange(r)}
            {r.eventDay && !r.eventEndDate ? ` (${r.eventDay})` : ''}
            {showStudent && ` · ${r.studentName} (${r.registerNumber}) · Year ${r.year} Sec ${r.section}`}
            {showAdvisor && ` · Advisor: ${r.advisorName}`}
            {!showStudent && ` · Advisor: ${r.advisorName}`}
          </p>
        </div>
        <span className={`${styles.status} ${styles[`status_${st.tone}`]}`}>{st.label}</span>
      </header>

      <p className={styles.desc}>{r.description}</p>
      {r.teamMembers?.length > 0 && <p className={styles.muted}>Team: {r.teamMembers.join(', ')}</p>}

      {showStepper && <Stepper r={r} />}

      {(r.advisorRemarks || r.hodRemarks) && (
        <div className={styles.remarks}>
          {r.advisorRemarks && <p><strong>Advisor:</strong> {r.advisorRemarks}</p>}
          {r.hodRemarks && <p><strong>HOD:</strong> {r.hodRemarks}</p>}
        </div>
      )}

      {r.files?.length > 0 && (
        <div className={styles.attachments}>
          <span className={styles.muted}>Evidence:</span>
          {r.files.map((f) => <FileLink key={f.id} file={f} />)}
        </div>
      )}

      {r.resultStatus && r.resultStatus !== 'PENDING' && (
        <p className={styles.result}>
          {r.resultStatus === 'WON' ? '🏆 Won' : '🎖️ Participated'} · {r.resultProjectName}
          {r.resultDescription ? ` · ${r.resultDescription}` : ''}
        </p>
      )}
      {children && <div className={styles.actions}>{children}</div>}
    </article>
  );
}

/// The files are in a private bucket, so there is no URL to render up front.
/// Opening one asks the server for a signed URL good for five minutes.
function FileLink({ file }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const open = async () => {
    setBusy(true);
    setError('');
    try {
      const url = await fileUrl(file.id);
      window.open(url, '_blank', 'noopener,noreferrer');
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <button type="button" className={styles.fileChip} onClick={open} disabled={busy}>
        {busy ? 'Opening…' : kindLabel(file.kind)}
        {file.sizeBytes ? ` · ${humanSize(file.sizeBytes)}` : ''}
      </button>
      {error && <span className={styles.fileError}>{error}</span>}
    </>
  );
}

function PhotoTile({ file }) {
  const [src, setSrc] = useState(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    fileUrl(file.id)
      .then((url) => !cancelled && setSrc(url))
      .catch(() => !cancelled && setFailed(true));
    return () => { cancelled = true; };
  }, [file.id]);

  return (
    <figure className={styles.photoTile}>
      {src && !failed ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={src} alt={kindLabel(file.kind)} onError={() => setFailed(true)} />
      ) : (
        <div className={styles.photoPlaceholder}>{failed ? 'Unavailable' : 'Loading…'}</div>
      )}
      <figcaption>{kindLabel(file.kind)}</figcaption>
    </figure>
  );
}

function ExportMenu({ label, onSelect }) {
  const [open, setOpen] = useState(false);
  return (
    <div className={styles.exportWrap}>
      <button type="button" className={styles.primaryBtn} onClick={() => setOpen((o) => !o)}>
        {label} ▾
      </button>
      {open && (
        <ul className={styles.exportMenu}>
          {[['pdf', 'PDF', 'With photographs'],
            ['word', 'Word', 'With photographs'],
            ['excel', 'Excel', 'Photographs listed by name']].map(([value, name, hint]) => (
              <li key={value}>
                <button
                  type="button"
                  onClick={() => { setOpen(false); onSelect(value); }}
                >
                  <strong>{name}</strong>
                  <small>{hint}</small>
                </button>
              </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function Stepper({ r }) {
  const s = r.status;
  const steps = [
    { label: 'Submitted', state: 'done' },
    {
      label: 'Class advisor',
      state: s === 'PENDING_ADVISOR' ? 'active' : s === 'REJECTED_ADVISOR' ? 'rejected' : 'done',
    },
    {
      label: 'HOD',
      state: s === 'APPROVED_BY_ADVISOR' ? 'active'
        : s === 'APPROVED' ? 'done'
          : s === 'REJECTED_HOD' ? 'rejected' : '',
    },
    {
      label: 'Sanctioned',
      state: s === 'APPROVED' ? 'done' : s.startsWith('REJECTED') ? 'rejected' : '',
    },
  ];
  return (
    <div className={styles.stepper}>
      {steps.map((step) => (
        <div key={step.label} className={`${styles.step} ${step.state ? styles[`step_${step.state}`] : ''}`}>
          <span className={styles.stepDot} />
          {step.label}
        </div>
      ))}
    </div>
  );
}

function TopBar({ subtitle = 'Department of Information Technology', children }) {
  return (
    <header className={styles.topNav}>
      <div className={styles.topNavInner}>
        <Link href="/" className={styles.brandGroup}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/college_logo.png" alt="SMVEC logo" className={styles.brandLogo} />
          <span className={styles.brandInfo}>
            <span className={styles.brandTitle}>SMVEC-IT OD PORTAL</span>
            <span className={styles.brandSubtitle}>{subtitle}</span>
          </span>
        </Link>
        <div className={styles.navActions}>{children}</div>
      </div>
    </header>
  );
}

function Tabs({ value, onChange, items }) {
  return (
    <div className={styles.tabs} role="tablist">
      {items.map(([v, label]) => (
        <button
          key={v}
          type="button"
          role="tab"
          aria-selected={value === v}
          className={value === v ? styles.tabActive : ''}
          onClick={() => onChange(v)}
        >
          {label}
        </button>
      ))}
    </div>
  );
}

function Modal({ title, onClose, children }) {
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div className={styles.modalBackdrop} onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className={styles.modalBox} role="dialog" aria-modal="true" aria-label={title}>
        <div className={styles.modalHeader}>
          <h3 className={styles.modalTitle}>{title}</h3>
          <button type="button" className={styles.closeBtn} onClick={onClose} aria-label="Close">✕</button>
        </div>
        {children}
      </div>
    </div>
  );
}

// Wraps a single control in a <label>; use `group` for multi-control fields.
function Field({ label, group, children }) {
  const Tag = group ? 'div' : 'label';
  return (
    <Tag className={styles.field}>
      <span className={styles.label}>{label}</span>
      {children}
    </Tag>
  );
}

function Kpi({ label, value }) {
  return (
    <div className={styles.kpi}>
      <span className={styles.kpiValue}>{value}</span>
      <span className={styles.kpiLabel}>{label}</span>
    </div>
  );
}

function Empty({ text, action }) {
  return (
    <div className={styles.empty}>
      <p>{text}</p>
      {action}
    </div>
  );
}

function ErrorBox({ text }) {
  if (!text) return null;
  return <div className={styles.error} role="alert">{text}</div>;
}
