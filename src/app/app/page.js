'use client';

// Web portal for the SMVEC OD system. It talks to the same /api/mobile backend
// as the Flutter app, so logins and OD data are shared between web and mobile.
//
// Clerk is the only way in. Clerk verifies the college email address (its own
// emails, so the app sends none), and the portal then trades the Clerk session
// token for an app session token through CLERK_LOGIN. The app token is held in
// React state only - Clerk already persists the real session, so there is
// nothing to keep in localStorage.

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { SignIn, useAuth } from '@clerk/nextjs';
import styles from './app.module.css';

const API = '/api/mobile';
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

async function api(action, payload = {}, token) {
  let res;
  try {
    res = await fetch(API, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
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
  const { isLoaded, isSignedIn, getToken, signOut } = useAuth();

  // null = not exchanged yet. Once set, either `session` or `pending` is filled.
  const [session, setSession] = useState(null);
  const [pending, setPending] = useState(null); // { email, regToken } for a new profile
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(true);

  const signOutEverywhere = useCallback(() => {
    setSession(null);
    setPending(null);
    signOut();
  }, [signOut]);

  // Trade the Clerk session for an app session as soon as Clerk is ready.
  useEffect(() => {
    if (!isLoaded) return undefined;
    let cancelled = false;
    (async () => {
      if (!isSignedIn) {
        if (!cancelled) {
          setSession(null);
          setPending(null);
          setBusy(false);
        }
        return;
      }
      setBusy(true);
      try {
        const clerkToken = await getToken();
        const res = await api('CLERK_LOGIN', {}, clerkToken);
        if (cancelled) return;
        if (res.needsRegistration) {
          setPending({ email: res.email, regToken: res.regToken });
          setSession(null);
        } else {
          setSession({ token: res.token, user: res.user });
          setPending(null);
        }
        setError('');
      } catch (err) {
        if (!cancelled) setError(err.message);
      } finally {
        if (!cancelled) setBusy(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [isLoaded, isSignedIn, getToken]);

  const onUserUpdate = (user) => setSession((s) => (s ? { ...s, user } : s));

  if (!isLoaded || busy) {
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

  if (!isSignedIn) return <SignInView />;

  // Signed in with Clerk but the server refused (wrong domain, unverified, …).
  if (error && !session && !pending) {
    return (
      <div className={styles.appContainer}>
        <div className={styles.authContainer}>
          <div className={styles.authCard}>
            <ErrorBox text={error} />
            <button type="button" className={styles.dangerBtn} onClick={signOutEverywhere}>
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
        regToken={pending.regToken}
        onDone={(s) => {
          setSession(s);
          setPending(null);
        }}
        onCancel={signOutEverywhere}
      />
    );
  }

  if (!session) return <SignInView />;
  return <Dashboard session={session} onLogout={signOutEverywhere} onUserUpdate={onUserUpdate} />;
}

// ---------------------------------------------------------------------------
// Sign in (handled entirely by Clerk)
// ---------------------------------------------------------------------------

function SignInView() {
  return (
    <div className={styles.appContainer}>
      <div className={styles.authContainer}>
        <div className={styles.authCard}>
          <div className={styles.authHead}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/college_logo.png" alt="SMVEC" className={styles.authLogo} />
            <h1 className={styles.authTitle}>SMVEC OD Portal</h1>
            <p className={styles.authSubtitle}>
              Department of Information Technology. Sign in with your official {DOMAIN} account.
            </p>
          </div>
          <SignIn routing="hash" />
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

function RegisterView({ email, regToken, onDone, onCancel }) {
  const [role, setRole] = useState('STUDENT');
  const [form, setForm] = useState({ name: '', rollNumber: '', year: '', section: '', batch: currentBatch() });
  const [staffCode, setStaffCode] = useState('');
  const [advisorEmail, setAdvisorEmail] = useState('');
  const [advisors, setAdvisors] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const set = (k) => (ev) => setForm((f) => ({ ...f, [k]: ev.target.value }));

  // Needed before the student has a session, so ADVISORS is public.
  useEffect(() => {
    let cancelled = false;
    api('ADVISORS')
      .then((res) => !cancelled && setAdvisors(res.advisors || []))
      .catch(() => !cancelled && setAdvisors([]));
    return () => {
      cancelled = true;
    };
  }, []);

  const submit = async (ev) => {
    ev.preventDefault();
    setBusy(true);
    setError('');
    try {
      const payload = { role, regToken, name: form.name, year: form.year, section: form.section };
      if (role === 'STUDENT') {
        payload.rollNumber = form.rollNumber;
        payload.advisorEmail = advisorEmail;
      } else {
        payload.batch = form.batch;
        payload.staffCode = staffCode;
      }
      const res = await api('REGISTER', payload);
      onDone({ token: res.token, user: res.user });
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
          <Field label="I am a">
            <div className={styles.roleSelector}>
              {[
                ['STUDENT', 'Student'],
                ['STAFF', 'Class Advisor'],
              ].map(([v, label]) => (
                <button
                  key={v}
                  type="button"
                  className={role === v ? styles.roleTabActive : styles.roleTab}
                  onClick={() => setRole(v)}
                >
                  {label}
                </button>
              ))}
            </div>
          </Field>

          <Field label="Full name">
            <input className={styles.input} value={form.name} onChange={set('name')} required maxLength={80} />
          </Field>

          {role === 'STUDENT' && (
            <>
              <Field label="Register number">
                <input className={styles.input} value={form.rollNumber} onChange={set('rollNumber')} required maxLength={30} />
              </Field>
              <Field label="Class advisor">
                {advisors === null ? (
                  <p className={styles.muted}>Loading class advisors…</p>
                ) : advisors.length === 0 ? (
                  <p className={styles.muted}>
                    No class advisors have registered yet. Your advisor needs to sign in once
                    before you can be attached to them.
                  </p>
                ) : (
                  <select
                    className={styles.input}
                    value={advisorEmail}
                    onChange={(ev) => setAdvisorEmail(ev.target.value)}
                    required
                  >
                    <option value="">Select your class advisor</option>
                    {advisors.map((a) => (
                      <option key={a.email} value={a.email}>
                        {a.name} — Year {a.year} {a.section}
                      </option>
                    ))}
                  </select>
                )}
              </Field>
            </>
          )}

          <Field label="Year" group>
            <select className={styles.input} value={form.year} onChange={set('year')} required>
              <option value="">Select year</option>
              {YEARS.map((y) => (
                <option key={y} value={y}>{y}</option>
              ))}
            </select>
          </Field>

          <Field label="Section" group>
            <select className={styles.input} value={form.section} onChange={set('section')} required>
              <option value="">Select section</option>
              {SECTIONS.map((s) => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
          </Field>

          {role === 'STAFF' && (
            <>
              <Field label="Batch">
                <input className={styles.input} value={form.batch} onChange={set('batch')} required placeholder="2023-2027" />
              </Field>
              <Field label="Staff code">
                <input
                  className={styles.input}
                  type="password"
                  value={staffCode}
                  onChange={(ev) => setStaffCode(ev.target.value)}
                  required
                  placeholder="Provided by the department"
                />
              </Field>
            </>
          )}

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
  const { token, user } = session;
  const [data, setData] = useState({ requests: [], notifications: [], auditLogs: [] });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showNotifs, setShowNotifs] = useState(false);
  const [toast, setToast] = useState('');

  const call = useCallback(
    async (action, payload) => {
      try {
        return await api(action, payload, token);
      } catch (err) {
        if (err.status === 401) onLogout();
        throw err;
      }
    },
    [token, onLogout]
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

  const roleName = { STUDENT: 'Student portal', STAFF: 'Class advisor portal', HOD: 'HOD portal' }[user.role];
  const badgeClass = { STUDENT: styles.badgeStudent, STAFF: styles.badgeStaff, HOD: styles.badgeHod }[user.role];
  const ctx = { user, call, upsert, refresh, setToast, onUserUpdate };

  return (
    <div className={styles.appContainer}>
      <TopBar subtitle={roleName}>
        <span className={`${styles.roleBadge} ${badgeClass}`}>
          {user.name}
          {user.role === 'STUDENT' && user.rollNumber ? ` · ${user.rollNumber}` : ''}
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
        ) : user.role === 'STAFF' ? (
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
  const [resultFor, setResultFor] = useState(null);
  const reqs = data.requests;
  const count = (fn) => reqs.filter(fn).length;

  return (
    <>
      <section className={styles.banner}>
        <div>
          <h2 className={styles.bannerTitle}>Hello, {user.name}</h2>
          <p className={styles.bannerSub}>
            {user.rollNumber} · Year {user.year} · Section {user.section} · {user.department}
          </p>
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
      teamMembers: [`${user.name} (${user.rollNumber || ''})`],
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
  const [status, setStatus] = useState('PARTICIPATION');
  const [projectName, setProjectName] = useState(request.eventName);
  const [description, setDescription] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (ev) => {
    ev.preventDefault();
    setBusy(true);
    setError('');
    try {
      const res = await call('SUBMIT_RESULT', { reqId: request.id, status, projectName, description });
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
              ['PARTICIPATION', 'Participated'],
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
  const [editClass, setEditClass] = useState(false);
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
            Class advisor · Year {user.year} · Section {user.section} · Batch {user.batch}
          </p>
        </div>
        <button type="button" className={styles.bannerBtn} onClick={() => setEditClass(true)}>Edit class details</button>
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

      {editClass && <ClassModal ctx={ctx} onClose={() => setEditClass(false)} />}
      {deciding && <DecisionModal ctx={ctx} action="ADVISOR_DECIDE" {...deciding} onClose={() => setDeciding(null)} />}
    </>
  );
}

function ClassModal({ ctx, onClose }) {
  const { user, call, onUserUpdate, setToast } = ctx;
  const [form, setForm] = useState({ year: String(user.year || ''), section: user.section || '', batch: user.batch || currentBatch() });
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (ev) => {
    ev.preventDefault();
    setBusy(true);
    setError('');
    try {
      const res = await call('UPDATE_CLASS', { ...form, year: Number(form.year) });
      onUserUpdate(res.user);
      setToast('Class details updated.');
      onClose();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title="Class details" onClose={onClose}>
      <form onSubmit={submit} className={styles.form}>
        <div className={styles.grid2}>
          <Field label="Year">
            <select className={styles.input} value={form.year} onChange={(e) => setForm({ ...form, year: e.target.value })} required>
              {YEARS.map((y) => (
                <option key={y} value={y}>Year {y}</option>
              ))}
            </select>
          </Field>
          <Field label="Section">
            <select className={styles.input} value={form.section} onChange={(e) => setForm({ ...form, section: e.target.value })} required>
              {SECTIONS.map((s) => (
                <option key={s} value={s}>Sec {s}</option>
              ))}
            </select>
          </Field>
        </div>
        <Field label="Batch (e.g. 2023-2027)">
          <input className={styles.input} value={form.batch} onChange={(e) => setForm({ ...form, batch: e.target.value })} required />
        </Field>
        <ErrorBox text={error} />
        <button type="submit" className={styles.primaryBtn} disabled={busy}>
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
      [r.studentName, r.rollNumber, r.eventName, r.advisorName, r.id, r.eventType].some((v) => String(v || '').toLowerCase().includes(q))
    );
  }, [tab, reqs, awaiting, query]);

  const exportCsv = () => {
    const cols = ['id', 'studentName', 'rollNumber', 'year', 'section', 'advisorName', 'eventType', 'eventName', 'eventDate', 'submissionType', 'status', 'resultStatus', 'createdAt'];
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
          {r.studentName} ({r.rollNumber}) · {r.eventType} on {fmtDate(r.eventDate)}
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
            {showStudent && ` · ${r.studentName} (${r.rollNumber}) · Year ${r.year} Sec ${r.section}`}
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
