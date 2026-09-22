'use client';

// Web portal for the SMVEC OD system. It talks to the same /api/mobile backend
// as the Flutter app, so logins and OD data are shared between web and mobile.
//
// Sign-in is Firebase, the same identity the Android app uses, so a student
// who registers on one sees their data on the other. The portal holds no
// session of its own: every call carries a fresh Firebase ID token and the
// server decides what the caller may do.

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import {
  describeAuthError, firebaseReady, idToken, signInWithGoogle, signOut, watchAuth,
} from '@/lib/firebase-client';
import styles from './app.module.css';

const API = '/api/v2';
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

/// One POST per call. The Firebase token is fetched here rather than passed
/// in, and an expired one is re-minted and retried once - a session that aged
/// out in another tab should not look like a failure.
async function api(action, payload = {}, { authenticated = true, retried = false } = {}) {
  let token = null;
  if (authenticated) {
    token = await idToken(retried);
    if (!token) {
      throw Object.assign(new Error('You are not signed in. Please sign in again.'), { status: 401 });
    }
  }

  let res;
  try {
    res = await fetch(API, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify({ action, payload }),
    });
  } catch {
    throw Object.assign(new Error('Could not reach the server. Check your connection.'), { status: 0 });
  }

  let data;
  try {
    data = await res.json();
  } catch {
    throw Object.assign(new Error(`Unexpected server response (${res.status}).`), { status: res.status });
  }

  if (res.status === 401 && authenticated && !retried) {
    return api(action, payload, { authenticated, retried: true });
  }
  if (!res.ok || data.success !== true) {
    throw Object.assign(new Error(data.error || 'Something went wrong.'), { status: res.status });
  }
  return data;
}

function currentBatch() {
  const y = new Date().getFullYear();
  return `${y - 1}-${y + 3}`;
}

const fmtDate = (iso) => (iso ? new Date(iso).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : '');
const fmtTime = (iso) => (iso ? new Date(iso).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '');

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function PortalPage() {
  // Read from the build-time config, so it is settled before the first paint
  // and there is nothing to discover in an effect.
  const configured = firebaseReady();

  const [firebaseUser, setFirebaseUser] = useState(configured ? undefined : null);
  const [session, setSession] = useState(null);
  const [pending, setPending] = useState(null); // { email, name } for a new profile
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  // Firebase tells us whether anyone is signed in, including after a reload.
  // Signing out clears the profile here rather than in a second effect, so the
  // two never disagree for a render.
  useEffect(() => {
    if (!configured) return undefined;
    return watchAuth((user) => {
      setFirebaseUser(user);
      if (!user) {
        setSession(null);
        setPending(null);
      }
    });
  }, [configured]);

  // Once Firebase has a user, ask the server who they are.
  useEffect(() => {
    if (!firebaseUser) return undefined;

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
        // The server refused this account - wrong domain, or disabled. Signing
        // out is the only way forward, so make that the offered action.
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
    await signOut().catch(() => {});
    setSession(null);
    setPending(null);
    setError('');
  }, []);

  const onUserUpdate = (user) => setSession((s) => (s ? { ...s, user } : s));

  if (firebaseUser === undefined || busy) {
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

  if (!firebaseUser) {
    return (
      <SignInView
        error={configured ? error : 'Sign-in is not set up for this site yet. Please use the Android app, or contact the department.'}
        disabled={!configured}
      />
    );
  }

  if (error && !session && !pending) {
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

  if (!session) return <SignInView error={error} />;
  return <Dashboard session={session} onLogout={onLogout} onUserUpdate={onUserUpdate} />;
}

// ---------------------------------------------------------------------------
// Sign in (Google, through Firebase)
// ---------------------------------------------------------------------------

function SignInView({ error, disabled = false }) {
  const [busy, setBusy] = useState(false);
  const [localError, setLocalError] = useState('');

  const google = async () => {
    setBusy(true);
    setLocalError('');
    try {
      await signInWithGoogle();
      // The auth listener in PortalPage takes over from here.
    } catch (err) {
      const message = describeAuthError(err);
      if (message) setLocalError(message);
    } finally {
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
            <h1 className={styles.authTitle}>SMVEC-IT OD Portal</h1>
            <p className={styles.authSubtitle}>
              Department of Information Technology. Sign in with your official {DOMAIN} account.
            </p>
          </div>

          <button
            type="button"
            className={styles.primaryBtn}
            onClick={google}
            disabled={busy || disabled}
          >
            {busy ? 'Opening Google…' : 'Continue with Google'}
          </button>

          {(localError || error) && <ErrorBox text={localError || error} />}

          <p className={styles.muted}>
            Staff can also sign in on the Android app with their department password.
          </p>
          <p className={styles.muted}>
            <Link href="/">Back to the main site</Link>
          </p>
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
  const sectionsFor = (year) => {
    const y = classes?.find((c) => String(c.year) === String(year));
    return y ? y.sections : [];
  };
  const sectionOptions = classes ? sectionsFor(form.year).map((s) => s.section) : SECTIONS;
  const resolvedAdvisor = sectionsFor(form.year).find((s) => s.section === form.section) || null;
  const onYearChange = (ev) => setForm((f) => ({ ...f, year: ev.target.value, section: '' }));

  // Needed before the student has a profile, so CLASSES is public.
  useEffect(() => {
    let cancelled = false;
    api('CLASSES', {}, { authenticated: false })
      .then((res) => !cancelled && setClasses(res.classes || []))
      .catch(() => !cancelled && setClasses([]));
    return () => {
      cancelled = true;
    };
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
              <input
                className={styles.input}
                value={form.name}
                onChange={set('name')}
                required
                maxLength={80}
              />
            </Field>

            <Field label="Register number">
              <input
                className={styles.input}
                value={form.rollNumber}
                onChange={set('rollNumber')}
                required
                maxLength={30}
              />
            </Field>

            <Field label="Year" group>
              <select className={styles.input} value={form.year} onChange={onYearChange} required>
                <option value="">Select year</option>
                {yearOptions.map((y) => (
                  <option key={y} value={y}>{y}</option>
                ))}
              </select>
            </Field>

            <Field label="Section" group>
              <select
                className={styles.input}
                value={form.section}
                onChange={set('section')}
                required
                disabled={!form.year}
              >
                <option value="">{form.year ? 'Select section' : 'Choose year first'}</option>
                {sectionOptions.map((s) => (
                  <option key={s} value={s}>{s}</option>
                ))}
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
            <button type="button" className={styles.linkBtn} onClick={onCancel}>
              Sign out
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}

function Dashboard({ session, onLogout, onUserUpdate }) {
  const { user } = session;
  const [data, setData] = useState({ requests: [], notifications: [], auditLogs: [] });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showNotifs, setShowNotifs] = useState(false);
  const [toast, setToast] = useState('');

  const call = useCallback(
    async (action, payload) => {
      try {
        return await api(action, payload);
      } catch (err) {
        if (err.status === 401) onLogout();
        throw err;
      }
    },
    [onLogout]
  );

  const refresh = useCallback(
    () =>
      call('SYNC')
        .then((res) => {
          setData(res.data);
          setError('');
        })
        .catch((err) => setError(err.message))
        .finally(() => setLoading(false)),
    [call]
  );

  // Sync on load and when the tab regains focus. No background polling, to keep
  // Upstash / Vercel usage low.
  useEffect(() => {
    refresh();
    const onVisible = () => document.visibilityState === 'visible' && refresh();
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [refresh]);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(''), 3500);
    return () => clearTimeout(t);
  }, [toast]);

  // Applies a server-updated request locally so we don't need another SYNC.
  const upsert = (request) =>
    setData((d) => {
      const rest = d.requests.filter((r) => r.id !== request.id);
      return { ...d, requests: [request, ...rest].sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt))) };
    });

  const roleName = { STUDENT: 'Student portal', ADVISOR: 'Class advisor portal', HOD: 'HOD portal' }[user.role];
  const badgeClass = { STUDENT: styles.badgeStudent, ADVISOR: styles.badgeStaff, HOD: styles.badgeHod }[user.role];
  const ctx = { user, call, upsert, refresh, setToast, onUserUpdate };

  return (
    <div className={styles.appContainer}>
      <TopBar subtitle={roleName}>
        <span className={`${styles.roleBadge} ${badgeClass}`}>
          {user.name}
          {user.role === 'STUDENT' && user.registerNumber ? ` · ${user.registerNumber}` : ''}
        </span>
        <button type="button" className={styles.iconBtn} onClick={() => setShowNotifs(true)} aria-label="Notifications">
          🔔
          {data.notifications.length > 0 && <span className={styles.notifBadge}>{data.notifications.length}</span>}
        </button>
        <button type="button" className={styles.ghostBtn} onClick={refresh}>Refresh</button>
        <button type="button" className={styles.dangerBtn} onClick={onLogout}>Sign out</button>
      </TopBar>

      <main className={styles.main}>
        {error && <ErrorBox text={error} />}
        {loading ? (
          <p className={styles.muted}>Loading…</p>
        ) : user.role === 'STUDENT' ? (
          <StudentView data={data} ctx={ctx} />
        ) : user.role === 'ADVISOR' ? (
          <AdvisorView data={data} ctx={ctx} />
        ) : (
          <HodView data={data} ctx={ctx} />
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

function StudentView({ data, ctx }) {
  const { user } = ctx;
  const [showNew, setShowNew] = useState(false);
  const [editClass, setEditClass] = useState(false);
  const [resultFor, setResultFor] = useState(null);
  const reqs = data.requests;
  const count = (fn) => reqs.filter(fn).length;

  return (
    <>
      <section className={styles.banner}>
        <div>
          <h2 className={styles.bannerTitle}>Hello, {user.name}</h2>
          <p className={styles.bannerSub}>
            {user.registerNumber} · Year {user.year} · Section {user.section} · {user.department}
          </p>
          <button type="button" className={styles.linkBtn} onClick={() => setEditClass(true)}>
            Wrong class?
          </button>
        </div>
        <button type="button" className={styles.bannerBtn} onClick={() => setShowNew(true)}>+ New OD request</button>
      </section>

      <div className={styles.kpiGrid}>
        <Kpi label="Total" value={reqs.length} />
        <Kpi label="Pending" value={count((r) => r.status === 'PENDING_ADVISOR' || r.status === 'APPROVED_BY_ADVISOR')} />
        <Kpi label="Approved" value={count((r) => r.status === 'APPROVED')} />
        <Kpi label="Rejected" value={count((r) => r.status.startsWith('REJECTED'))} />
      </div>

      <h3 className={styles.sectionHeading}>My OD requests</h3>
      {reqs.length === 0 ? (
        <Empty text="You haven't submitted any OD requests yet." action={<button className={styles.primaryBtn} onClick={() => setShowNew(true)}>Submit your first request</button>} />
      ) : (
        <div className={styles.list}>
          {reqs.map((r) => (
            <RequestCard key={r.id} r={r} showStepper>
              {r.status === 'APPROVED' && r.resultStatus === 'PENDING' && (
                <button className={styles.secondaryBtn} onClick={() => setResultFor(r)}>Add event result</button>
              )}
            </RequestCard>
          ))}
        </div>
      )}

      {showNew && <NewOdModal ctx={ctx} onClose={() => setShowNew(false)} />}
      {editClass && <ClassModal ctx={ctx} onClose={() => setEditClass(false)} />}
      {resultFor && <ResultModal ctx={ctx} request={resultFor} onClose={() => setResultFor(null)} />}
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
      description: '',
      teamMembers: [`${user.name} (${user.registerNumber || ''})`],
    };
  });
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value });

  const submit = async (ev) => {
    ev.preventDefault();
    setError('');
    setBusy(true);
    try {
      const day = DAYS[new Date(`${form.eventDate}T00:00:00`).getDay()];
      const res = await call('CREATE_OD', { ...form, eventDay: day, teamMembers: form.submissionType === 'TEAM' ? form.teamMembers : [] });
      upsert(res.request);
      setToast('OD request submitted to your advisor.');
      onClose();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title="New OD request" onClose={onClose}>
      <form onSubmit={submit} className={styles.form}>
        {/* The advisor is fixed on the profile, so this only says where it goes. */}
        <Field label="Class advisor">
          <p className={styles.muted}>{user.advisorName || 'Not set on your profile'}</p>
        </Field>
        <div className={styles.grid2}>
          <Field label="Event type">
            <select className={styles.input} value={form.eventType} onChange={set('eventType')}>
              {EVENT_TYPES.map((t) => (
                <option key={t}>{t}</option>
              ))}
            </select>
          </Field>
          <Field label="Event date">
            <input type="date" className={styles.input} value={form.eventDate} onChange={set('eventDate')} required />
          </Field>
        </div>
        <Field label="Event name">
          <input className={styles.input} value={form.eventName} onChange={set('eventName')} maxLength={120} required />
        </Field>
        <Field label="Participation" group>
          <div className={styles.segmented}>
            {['SOLO', 'TEAM'].map((t) => (
              <button
                key={t}
                type="button"
                className={form.submissionType === t ? styles.segActive : ''}
                onClick={() => setForm({ ...form, submissionType: t })}
              >
                {t === 'SOLO' ? 'Solo' : 'Team'}
              </button>
            ))}
          </div>
        </Field>
        {form.submissionType === 'TEAM' && (
          <Field label="Team members (max 5)" group>
            <div className={styles.form}>
              {form.teamMembers.map((m, i) => (
                <div key={i} className={styles.inputWrap}>
                  <input
                    className={styles.input}
                    value={m}
                    placeholder="Name (Register number)"
                    onChange={(e) => {
                      const tm = [...form.teamMembers];
                      tm[i] = e.target.value;
                      setForm({ ...form, teamMembers: tm });
                    }}
                  />
                  {i > 0 && (
                    <button type="button" className={styles.inputAddon} onClick={() => setForm({ ...form, teamMembers: form.teamMembers.filter((_, j) => j !== i) })}>
                      Remove
                    </button>
                  )}
                </div>
              ))}
              {form.teamMembers.length < 5 && (
                <button type="button" className={styles.linkBtn} onClick={() => setForm({ ...form, teamMembers: [...form.teamMembers, ''] })}>
                  + Add member
                </button>
              )}
            </div>
          </Field>
        )}
        <Field label="Description">
          <textarea className={styles.input} rows={4} value={form.description} onChange={set('description')} maxLength={1000} required />
        </Field>
        <ErrorBox text={error} />
        <button type="submit" className={styles.primaryBtn} disabled={busy}>
          {busy ? 'Submitting…' : 'Submit request'}
        </button>
      </form>
    </Modal>
  );
}

function ResultModal({ ctx, request, onClose }) {
  const { call, upsert, setToast } = ctx;
  const [status, setStatus] = useState('PARTICIPATED');
  const [projectName, setProjectName] = useState(request.eventName);
  const [prize, setPrize] = useState('');
  const [prizeDetails, setPrizeDetails] = useState('');
  const [description, setDescription] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

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
            {[
              ['PARTICIPATED', 'Participated'],
              ['WON', 'Won a prize'],
            ].map(([v, l]) => (
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
        <ErrorBox text={error} />
        <button type="submit" className={styles.primaryBtn} disabled={busy}>
          {busy ? 'Saving…' : 'Save result'}
        </button>
      </form>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
// Class advisor (staff)
// ---------------------------------------------------------------------------

function AdvisorView({ data, ctx }) {
  const { user } = ctx;
  const [tab, setTab] = useState('PENDING');
  const [deciding, setDeciding] = useState(null);
  const pending = data.requests.filter((r) => r.status === 'PENDING_ADVISOR');
  const reviewed = data.requests.filter((r) => r.status !== 'PENDING_ADVISOR');
  const shown = tab === 'PENDING' ? pending : reviewed;

  return (
    <>
      <section className={styles.banner}>
        <div>
          <h2 className={styles.bannerTitle}>{user.name}</h2>
          <p className={styles.bannerSub}>
            {/* Assigned by the department, so it is shown rather than edited. */}
            Class advisor ·{' '}
            {(user.classes || []).length
              ? (user.classes || [])
                .map((c) => `Year ${c.year} Section ${c.section}`)
                .join(', ')
              : 'No class assigned yet'}
          </p>
        </div>
      </section>

      <div className={styles.kpiGrid}>
        <Kpi label="Awaiting review" value={pending.length} />
        <Kpi label="Forwarded to HOD" value={data.requests.filter((r) => r.status === 'APPROVED_BY_ADVISOR').length} />
        <Kpi label="Approved" value={data.requests.filter((r) => r.status === 'APPROVED').length} />
        <Kpi label="Rejected" value={data.requests.filter((r) => r.status.startsWith('REJECTED')).length} />
      </div>

      <Tabs
        value={tab}
        onChange={setTab}
        items={[
          ['PENDING', `Pending (${pending.length})`],
          ['REVIEWED', `Reviewed (${reviewed.length})`],
        ]}
      />
      {shown.length === 0 ? (
        <Empty text={tab === 'PENDING' ? 'No requests waiting for your review.' : 'Nothing reviewed yet.'} />
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

function ClassModal({ ctx, onClose }) {
  const { user, call, onUserUpdate, setToast } = ctx;
  const [form, setForm] = useState({
    year: String(user.year || ''), section: user.section || '',
  });
  const [classes, setClasses] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    api('CLASSES', {}, { authenticated: false })
      .then((res) => !cancelled && setClasses(res.classes || []))
      .catch(() => !cancelled && setClasses([]));
    return () => {
      cancelled = true;
    };
  }, []);

  const sectionsFor = (year) => {
    const y = classes?.find((c) => String(c.year) === String(year));
    return y ? y.sections : [];
  };
  const yearOptions = classes ? classes.map((c) => c.year) : YEARS;
  const sectionOptions = classes ? sectionsFor(form.year).map((s) => s.section) : SECTIONS;
  const advisor = sectionsFor(form.year).find((s) => s.section === form.section) || null;

  const submit = async (ev) => {
    ev.preventDefault();
    setBusy(true);
    setError('');
    try {
      const res = await call('CHANGE_CLASS', {
        year: Number(form.year), section: form.section,
      });
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
            <select
              className={styles.input}
              value={form.year}
              onChange={(e) => setForm({ year: e.target.value, section: '' })}
              required
            >
              <option value="">Select year</option>
              {yearOptions.map((y) => (
                <option key={y} value={y}>Year {y}</option>
              ))}
            </select>
          </Field>
          <Field label="Section">
            <select
              className={styles.input}
              value={form.section}
              onChange={(e) => setForm({ ...form, section: e.target.value })}
              required
              disabled={!form.year}
            >
              <option value="">{form.year ? 'Select section' : 'Choose year first'}</option>
              {sectionOptions.map((s) => (
                <option key={s} value={s}>Sec {s}</option>
              ))}
            </select>
          </Field>
        </div>
        <Field label="Class advisor">
          <p className={styles.muted}>
            {classes === null
              ? 'Loading classes…'
              : advisor
                ? advisor.advisorName
                : 'Choose your year and section'}
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
// HOD
// ---------------------------------------------------------------------------

function HodView({ data, ctx }) {
  const [tab, setTab] = useState('AWAITING');
  const [query, setQuery] = useState('');
  const [deciding, setDeciding] = useState(null);
  const reqs = data.requests;
  const awaiting = reqs.filter((r) => r.status === 'APPROVED_BY_ADVISOR');

  const shown = useMemo(() => {
    const base = tab === 'AWAITING' ? awaiting : reqs;
    const q = query.trim().toLowerCase();
    if (!q) return base;
    return base.filter((r) =>
      [r.studentName, r.registerNumber, r.eventName, r.advisorName, r.id, r.eventType].some((v) => String(v || '').toLowerCase().includes(q))
    );
  }, [tab, reqs, awaiting, query]);

  const exportCsv = () => {
    const cols = ['id', 'studentName', 'registerNumber', 'year', 'section', 'advisorName', 'eventType', 'eventName', 'eventDate', 'submissionType', 'status', 'resultStatus', 'createdAt'];
    const escape = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
    const csv = [cols.join(','), ...reqs.map((r) => cols.map((c) => escape(r[c])).join(','))].join('\n');
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `SMVEC_IT_OD_Report_${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <>
      <section className={styles.banner}>
        <div>
          <h2 className={styles.bannerTitle}>HOD dashboard</h2>
          <p className={styles.bannerSub}>Department of Information Technology · Final OD sanction</p>
        </div>
        <button type="button" className={styles.bannerBtn} onClick={exportCsv} disabled={!reqs.length}>Export CSV</button>
      </section>

      <div className={styles.kpiGrid}>
        <Kpi label="Awaiting sanction" value={awaiting.length} />
        <Kpi label="With advisors" value={reqs.filter((r) => r.status === 'PENDING_ADVISOR').length} />
        <Kpi label="Approved" value={reqs.filter((r) => r.status === 'APPROVED').length} />
        <Kpi label="Prizes won" value={reqs.filter((r) => r.resultStatus === 'WON').length} />
      </div>

      <div className={styles.rowBetween}>
        <Tabs
          value={tab}
          onChange={setTab}
          items={[
            ['AWAITING', `Awaiting (${awaiting.length})`],
            ['ALL', `All (${reqs.length})`],
            ['AUDIT', 'Audit log'],
          ]}
        />
        {tab !== 'AUDIT' && (
          <input className={`${styles.input} ${styles.search}`} placeholder="Search student, event, advisor…" value={query} onChange={(e) => setQuery(e.target.value)} />
        )}
      </div>

      {tab === 'AUDIT' ? (
        data.auditLogs.length === 0 ? (
          <Empty text="No activity yet." />
        ) : (
          <div className={styles.tableWrap}>
            <table className={styles.table}>
              <thead>
                <tr><th>Time</th><th>Action</th><th>By</th><th>Details</th></tr>
              </thead>
              <tbody>
                {data.auditLogs.map((a) => (
                  <tr key={a.id + a.time}>
                    <td>{fmtTime(a.time)}</td>
                    <td>{a.action.replace(/_/g, ' ').toLowerCase()}</td>
                    <td>{a.actor}</td>
                    <td>{a.details}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )
      ) : shown.length === 0 ? (
        <Empty text={tab === 'AWAITING' ? 'Nothing waiting for your sanction.' : 'No requests found.'} />
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

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

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
      setToast(approve ? 'Request approved.' : 'Request rejected.');
      onClose();
    } catch (err) {
      setError(err.message);
      if (err.status === 409) ctx.refresh();
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title={`${approve ? 'Approve' : 'Reject'} · ${r.eventName}`} onClose={onClose}>
      <form onSubmit={submit} className={styles.form}>
        <p className={styles.muted}>
          {r.studentName} ({r.registerNumber}) · {r.eventType} on {fmtDate(r.eventDate)}
        </p>
        <Field label={approve ? 'Remarks (optional)' : 'Reason for rejection'}>
          <textarea className={styles.input} rows={3} value={remarks} onChange={(e) => setRemarks(e.target.value)} maxLength={500} required={!approve} />
        </Field>
        <ErrorBox text={error} />
        <button type="submit" className={approve ? styles.approveBtn : styles.rejectBtn} disabled={busy}>
          {busy ? 'Saving…' : approve ? 'Confirm approval' : 'Confirm rejection'}
        </button>
      </form>
    </Modal>
  );
}

function RequestCard({ r, showStudent, showAdvisor, showStepper, children }) {
  const st = STATUS[r.status] || { label: r.status, tone: 'pending' };
  return (
    <article className={styles.card}>
      <header className={styles.cardHeader}>
        <div>
          <div className={styles.metaRow}>
            <span className={styles.chip}>{r.eventType}</span>
            <span className={styles.chip}>{r.submissionType === 'TEAM' ? 'Team' : 'Solo'}</span>
            <span className={styles.idText}>{r.id}</span>
          </div>
          <h4 className={styles.cardEvent}>{r.eventName}</h4>
          <p className={styles.muted}>
            {fmtDate(r.eventDate)}
            {r.eventDay ? ` (${r.eventDay})` : ''}
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
      {r.files?.length > 0 && <Attachments files={r.files} />}
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

const FILE_KIND = {
  CERTIFICATE: 'Certificate',
  WINNING_PHOTO: 'Winning photo',
  EVENT_PHOTO: 'Event photo',
  SUPPORTING_DOCUMENT: 'Supporting document',
};

const fileSize = (bytes) => {
  if (!bytes) return '';
  const kb = bytes / 1024;
  return kb < 1024 ? `${Math.round(kb)} KB` : `${(kb / 1024).toFixed(1)} MB`;
};

/// The files are in a private bucket, so there is no URL to render up front.
/// Opening one asks the server for a signed URL good for five minutes.
function Attachments({ files }) {
  const [busyId, setBusyId] = useState(null);
  const [error, setError] = useState('');

  const open = async (file) => {
    setBusyId(file.id);
    setError('');
    try {
      const res = await api('FILE_URL', { fileId: file.id });
      window.open(res.url, '_blank', 'noopener,noreferrer');
    } catch (err) {
      setError(err.message);
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div className={styles.attachments}>
      <span className={styles.muted}>Evidence:</span>
      {files.map((f) => (
        <button
          key={f.id}
          type="button"
          className={styles.fileChip}
          onClick={() => open(f)}
          disabled={busyId === f.id}
        >
          {busyId === f.id ? 'Opening…' : `${FILE_KIND[f.kind] || 'Attachment'}`}
          {f.sizeBytes ? ` · ${fileSize(f.sizeBytes)}` : ''}
        </button>
      ))}
      {error && <span className={styles.fileError}>{error}</span>}
    </div>
  );
}

function Stepper({ r }) {
  const s = r.status;
  const steps = [
    { label: 'Submitted', state: 'done' },
    {
      label: 'Advisor',
      state: s === 'PENDING_ADVISOR' ? 'active' : s === 'REJECTED_ADVISOR' ? 'rejected' : 'done',
    },
    {
      label: 'HOD',
      state: s === 'APPROVED' ? 'done' : s === 'REJECTED_HOD' ? 'rejected' : s === 'APPROVED_BY_ADVISOR' ? 'active' : 'todo',
    },
  ];
  return (
    <ol className={styles.stepper}>
      {steps.map((st, i) => (
        <li key={st.label} className={`${styles.step} ${styles[`step_${st.state}`]}`}>
          <span className={styles.stepDot}>{st.state === 'done' ? '✓' : st.state === 'rejected' ? '✕' : i + 1}</span>
          {st.label}
        </li>
      ))}
    </ol>
  );
}

function TopBar({ subtitle = 'Department of Information Technology', children }) {
  return (
    <header className={styles.topNav}>
      <div className={styles.topNavInner}>
        <Link href="/" className={styles.brandGroup}>
          <img src="/college_logo.png" alt="SMVEC logo" className={styles.brandLogo} />
          <span className={styles.brandInfo}>
            <span className={styles.brandTitle}>SMVEC OD PORTAL</span>
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
        <button key={v} type="button" role="tab" aria-selected={value === v} className={value === v ? styles.tabActive : ''} onClick={() => onChange(v)}>
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
