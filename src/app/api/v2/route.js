// SMVEC OD API v2 - Firebase identity, Supabase Postgres storage.
//
// One POST endpoint taking { action, payload }, same shape the apps already
// use. Callers present a Firebase ID token; staff may instead exchange a
// password for one through PASSWORD_LOGIN.
//
// Every rule that matters is enforced here and again by database triggers, so
// no client and no future code path can approve out of order.

import bcrypt from 'bcryptjs';
import { NextResponse } from 'next/server';
import {
  HttpError, clean, dateOf, identify, passwordIdentify, publicUser, requestForActor, requireRole, sectionOf, signStaffToken, text, uuidOf, yearOf,
} from '@/lib/api-core';
import { audit, one, query, transaction } from '@/lib/db';
import { sendPush } from '@/lib/firebase-admin';
import {
  ALLOWED_MIME, MAX_BYTES, deleteObject, objectKeyFor, signedUrl,
  storageConfigured, uploadObject,
} from '@/lib/storage';

export const dynamic = 'force-dynamic';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

const json = (body, status = 200) => NextResponse.json(body, { status, headers: cors });

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

/// Records a notification and pushes it. The push is best effort; the row is
/// the durable part, so the in-app list is right even if FCM is unavailable.
async function notify(client, userId, { title, body, odRequestId, category }) {
  const runner = client || { query: (t, p) => query(t, p) };
  await runner.query(
    `insert into notifications (user_id, od_request_id, title, body, category)
     values ($1, $2, $3, $4, $5)`,
    [userId, odRequestId || null, title, body, category || null]
  );
  const user = await one('select fcm_token from users where id = $1', [userId]);
  if (!user?.fcm_token) return;
  const result = await sendPush(user.fcm_token, {
    title, body, data: { odRequestId: odRequestId || '', category: category || '' },
  });
  if (result === 'STALE') {
    await query('update users set fcm_token = null where id = $1', [userId]);
  } else if (result === true) {
    await query(
      `update notifications set pushed_at = now()
        where id = (select id from notifications where user_id = $1 order by created_at desc limit 1)`,
      [userId]
    );
  }
}

const hodUserIds = async () =>
  (await query('select u.id from staff s join users u on u.id = s.user_id where s.is_hod')).map((r) => r.id);

// ---------------------------------------------------------------------------
// Auth actions
// ---------------------------------------------------------------------------

async function session(auth) {
  if (auth.role === 'STUDENT') {
    const student = await one(
      `select s.id, s.register_number, s.name, s.year, s.section, s.profile_completed,
              c.is_active as class_active,
              st.name as advisor_name, st.email as advisor_email,
              st.is_active as advisor_active,
              coalesce(c.advisor_label, st.name) as advisor_display
         from students s
         left join class_assignments c on c.id = s.class_assignment_id
         left join staff st on st.id = c.staff_id
        where s.user_id = $1`,
      [auth.userId]
    );
    if (!student || !student.profile_completed) {
      return { success: true, needsRegistration: true, email: auth.email, name: auth.name };
    }

    // Their advisor has been removed, or the class was released with them.
    // Everything they have already filed still stands; they just cannot raise
    // a new OD until they say which class they are in now.
    const orphaned = !student.class_active || student.advisor_active === false;

    return {
      success: true,
      needsClassUpdate: orphaned,
      user: publicUser(auth, {
        registerNumber: student.register_number,
        name: student.name,
        year: student.year,
        section: student.section,
        advisorName: orphaned ? null : student.advisor_display,
        advisorEmail: orphaned ? null : student.advisor_email,
        needsClassUpdate: orphaned,
        photoUrl: auth.photoUrl,
      }),
    };
  }

  const classes = await query(
    `select year, section, coalesce(advisor_label, $2) as label, batch
       from class_assignments where staff_id = $1 and is_active order by year, section`,
    [auth.staffId, auth.name]
  );
  return {
    success: true,
    user: publicUser(auth, {
      classes: classes.map((c) => ({ year: c.year, section: c.section, label: c.label, batch: c.batch })),
    }),
  };
}

/// The department's class structure. Public: a student needs it before they
/// have a profile, and it exposes only the published class list.
async function classList() {
  const rows = await query(
    `select c.year, c.section, coalesce(c.advisor_label, s.name) as advisor_name,
            s.email as advisor_email, c.batch
       from class_assignments c join staff s on s.id = c.staff_id
      where c.is_active order by c.year, c.section`
  );
  const byYear = new Map();
  for (const r of rows) {
    if (!byYear.has(r.year)) byYear.set(r.year, []);
    byYear.get(r.year).push({
      section: r.section, advisorName: r.advisor_name, advisorEmail: r.advisor_email,
    });
  }
  return {
    success: true,
    classes: [...byYear.entries()].map(([year, sections]) => ({ year, sections })),
    advisors: rows.map((r) => ({
      name: r.advisor_name, email: r.advisor_email, year: r.year, section: r.section, batch: r.batch,
    })),
  };
}

/// First-time student profile. The advisor is derived from the class, never
/// supplied by the caller.
async function registerStudent(auth, p) {
  requireRole(auth, 'STUDENT');
  const year = yearOf(p.year);
  const section = sectionOf(p.section);

  const klass = await one(
    'select id, staff_id from class_assignments where year = $1 and section = $2 and is_active',
    [year, section]
  );
  if (!klass) throw new HttpError(400, `No class advisor is listed for Year ${year} Section ${section}.`);

  const name = text(p.name, 'Name', 80);
  const registerNumber = text(p.registerNumber ?? p.rollNumber, 'Register number', 30).toUpperCase();

  const clash = await one(
    'select id from students where register_number = $1 and user_id <> $2',
    [registerNumber, auth.userId]
  );
  if (clash) throw new HttpError(409, 'That register number is already registered.');

  await transaction(async (client) => {
    await client.query('update users set display_name = $1 where id = $2', [name, auth.userId]);
    await client.query(
      `insert into students (user_id, register_number, name, email, year, section,
                             class_assignment_id, profile_completed)
       values ($1, $2, $3, $4, $5, $6, $7, true)
       on conflict (user_id) do update
         set register_number = excluded.register_number, name = excluded.name,
             year = excluded.year, section = excluded.section,
             class_assignment_id = excluded.class_assignment_id, profile_completed = true`,
      [auth.userId, registerNumber, name, auth.email, year, section, klass.id]
    );
    await audit(client, {
      actorUserId: auth.userId, actorEmail: auth.email, actorRole: 'STUDENT',
      action: 'PROFILE_COMPLETED', entityType: 'student', entityId: auth.userId,
      details: { year, section, registerNumber },
    });
  });

  const fresh = await identifyAgain(auth);
  return session(fresh);
}

async function identifyAgain(auth) {
  const student = await one('select id, profile_completed, name from students where user_id = $1', [auth.userId]);
  return { ...auth, studentId: student?.id || null, profileCompleted: true, name: student?.name || auth.name };
}

/// Lets a student correct the class they registered under; the advisor follows.
/// Requests already filed keep the advisor who received them.
async function changeClass(auth, p) {
  requireRole(auth, 'STUDENT');
  const year = yearOf(p.year);
  const section = sectionOf(p.section);
  const klass = await one(
    'select id from class_assignments where year = $1 and section = $2 and is_active',
    [year, section]
  );
  if (!klass) throw new HttpError(400, `No class advisor is listed for Year ${year} Section ${section}.`);

  await query(
    'update students set year = $1, section = $2, class_assignment_id = $3 where user_id = $4',
    [year, section, klass.id, auth.userId]
  );
  await audit(null, {
    actorUserId: auth.userId, actorEmail: auth.email, actorRole: 'STUDENT',
    action: 'CLASS_CHANGED', entityType: 'student', entityId: auth.studentId,
    details: { year, section },
  });
  return session(await identifyAgain(auth));
}

// ---------------------------------------------------------------------------
// The HOD manages the class advisors
// ---------------------------------------------------------------------------

/// Everything the HOD needs to see about the department's advisors: who they
/// are, which classes they hold, how much history they carry, and whether they
/// are still serving. Never a password or a digest.
async function advisorRoster(auth) {
  requireRole(auth, 'HOD');
  const rows = await query(
    `select s.id, s.name, s.email, s.is_hod, s.is_active, s.retired_at,
            coalesce(json_agg(
              json_build_object('year', c.year, 'section', c.section)
              order by c.year, c.section
            ) filter (where c.id is not null), '[]') as classes,
            (select count(*) from od_requests r where r.advisor_staff_id = s.id) as request_count,
            (select count(*) from students st
               join class_assignments ca on ca.id = st.class_assignment_id
              where ca.staff_id = s.id and ca.is_active) as student_count
       from staff s
       left join class_assignments c on c.staff_id = s.id and c.is_active
      group by s.id
      order by s.is_hod desc, s.is_active desc, s.name`
  );

  // Which classes nobody is holding, so the HOD can see the gaps a removal left.
  const taken = await query(
    'select year, section from class_assignments where is_active order by year, section'
  );
  const held = new Set(taken.map((c) => `${c.year}-${c.section}`));

  return {
    success: true,
    advisors: rows.map((r) => ({
      id: r.id,
      name: r.name,
      email: r.email,
      isHod: r.is_hod,
      isActive: r.is_active,
      retiredAt: r.retired_at,
      classes: r.classes,
      requestCount: Number(r.request_count),
      studentCount: Number(r.student_count),
    })),
    heldClasses: [...held],
  };
}

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function advisorEmail(v) {
  const email = clean(v).toLowerCase();
  if (!EMAIL.test(email)) throw new HttpError(400, 'That is not a valid email address.');
  return email;
}

function advisorPassword(v, { required }) {
  const password = String(v ?? '');
  if (!password) {
    if (required) throw new HttpError(400, 'Give the advisor a password.');
    return null;
  }
  if (password.length < 8) {
    throw new HttpError(400, 'A password needs at least 8 characters.');
  }
  return password;
}

/// The classes an advisor is to hold, as {year, section} pairs.
function advisorClasses(v) {
  if (!Array.isArray(v)) return null;
  return v.map((c) => ({ year: yearOf(c?.year), section: sectionOf(c?.section) }));
}

/// Puts [staffId] in charge of exactly [classes] and nothing else.
///
/// A class already held by somebody else changes hands: the old assignment is
/// retired rather than deleted, so the students in it keep a trail and the
/// requests already filed keep the advisor who received them.
async function setClasses(client, staffId, classes) {
  if (!classes) return;
  const wanted = new Set(classes.map((c) => `${c.year}-${c.section}`));

  const current = await client.query(
    'select id, year, section from class_assignments where staff_id = $1 and is_active',
    [staffId]
  );
  for (const row of current.rows) {
    if (!wanted.has(`${row.year}-${row.section}`)) {
      await client.query('update class_assignments set is_active = false where id = $1', [row.id]);
    }
  }

  for (const c of classes) {
    const existing = await client.query(
      'select id, staff_id from class_assignments where year = $1 and section = $2 and is_active',
      [c.year, c.section]
    );
    if (existing.rows.length) {
      if (existing.rows[0].staff_id === staffId) continue;
      // Taking the class from whoever held it.
      await client.query(
        'update class_assignments set is_active = false where id = $1',
        [existing.rows[0].id]
      );
    }
    await client.query(
      'insert into class_assignments (staff_id, year, section) values ($1, $2, $3)',
      [staffId, c.year, c.section]
    );
  }
}

async function createAdvisor(auth, p) {
  requireRole(auth, 'HOD');
  const name = text(p.name, 'Name', 80);
  const email = advisorEmail(p.email);
  const password = advisorPassword(p.password, { required: true });
  const classes = advisorClasses(p.classes);

  const existing = await one('select id, is_active from staff where email = $1', [email]);
  if (existing?.is_active) {
    throw new HttpError(409, 'An advisor already uses that email address.');
  }

  const hash = await bcrypt.hash(password, 12);

  const staffId = await transaction(async (client) => {
    let id = existing?.id;

    if (id) {
      // The address belonged to an advisor who was removed. Bringing them back
      // keeps the ODs they handled attached to the same person.
      await client.query(
        `update staff set name = $1, password_hash = $2, is_active = true,
                          retired_at = null, updated_at = now()
          where id = $3`,
        [name, hash, id]
      );
      await client.query(
        `update users set display_name = $1, is_active = true, role = 'ADVISOR'
          where id = (select user_id from staff where id = $2)`,
        [name, id]
      );
    } else {
      const user = await client.query(
        `insert into users (email, role, display_name) values ($1, 'ADVISOR', $2)
         returning id`,
        [email, name]
      );
      const staff = await client.query(
        `insert into staff (user_id, name, email, password_hash) values ($1, $2, $3, $4)
         returning id`,
        [user.rows[0].id, name, email, hash]
      );
      id = staff.rows[0].id;
    }

    await setClasses(client, id, classes);
    await audit(client, {
      actorUserId: auth.userId, actorEmail: auth.email, actorRole: 'HOD',
      action: existing ? 'ADVISOR_RESTORED' : 'ADVISOR_CREATED',
      entityType: 'staff', entityId: id,
      details: { name, email, classes: (classes || []).map((c) => `${c.year}-${c.section}`) },
    });
    return id;
  });

  return { ...(await advisorRoster(auth)), staffId };
}

async function updateAdvisor(auth, p) {
  requireRole(auth, 'HOD');
  const staffId = uuidOf(p.staffId, 'No advisor was specified.');
  const current = await one('select * from staff where id = $1', [staffId]);
  if (!current) throw new HttpError(404, 'That advisor was not found.');
  if (!current.is_active) {
    throw new HttpError(409, 'That advisor has been removed. Add them again to bring them back.');
  }

  const name = p.name === undefined ? current.name : text(p.name, 'Name', 80);
  const email = p.email === undefined ? current.email : advisorEmail(p.email);
  const password = advisorPassword(p.password, { required: false });
  const classes = advisorClasses(p.classes);

  if (email !== current.email) {
    const clash = await one('select id from staff where email = $1 and id <> $2', [email, staffId]);
    if (clash) throw new HttpError(409, 'Another advisor already uses that email address.');
  }

  // The HOD's own classes are not a thing, and demoting themselves by accident
  // would lock the department out of this screen.
  if (current.is_hod && classes) {
    throw new HttpError(400, 'The HOD does not hold a class.');
  }

  const hash = password ? await bcrypt.hash(password, 12) : null;

  await transaction(async (client) => {
    await client.query(
      `update staff
          set name = $1, email = $2,
              password_hash = coalesce($3, password_hash),
              updated_at = now()
        where id = $4`,
      [name, email, hash, staffId]
    );
    await client.query(
      'update users set display_name = $1, email = $2 where id = $3',
      [name, email, current.user_id]
    );
    if (!current.is_hod) await setClasses(client, staffId, classes);

    await audit(client, {
      actorUserId: auth.userId, actorEmail: auth.email, actorRole: 'HOD',
      action: 'ADVISOR_UPDATED', entityType: 'staff', entityId: staffId,
      details: {
        name,
        email,
        passwordChanged: Boolean(hash),
        classes: classes ? classes.map((c) => `${c.year}-${c.section}`) : 'unchanged',
      },
    });
  });

  return advisorRoster(auth);
}

async function removeAdvisor(auth, p) {
  requireRole(auth, 'HOD');
  const staffId = uuidOf(p.staffId, 'No advisor was specified.');
  const current = await one('select * from staff where id = $1', [staffId]);
  if (!current) throw new HttpError(404, 'That advisor was not found.');
  if (current.is_hod) throw new HttpError(400, 'The HOD cannot be removed.');
  if (!current.is_active) throw new HttpError(409, 'That advisor has already been removed.');

  // Who is about to be left without an advisor, so the HOD is told before the
  // students find out.
  const affected = await query(
    `select st.name, st.register_number, ca.year, ca.section
       from students st
       join class_assignments ca on ca.id = st.class_assignment_id
      where ca.staff_id = $1 and ca.is_active
      order by ca.year, ca.section, st.name`,
    [staffId]
  );

  await transaction(async (client) => {
    // The trigger releases their classes; the requests they handled keep
    // pointing at them, which is what makes the old reports still read right.
    await client.query(
      'update staff set is_active = false, retired_at = now(), updated_at = now() where id = $1',
      [staffId]
    );
    await client.query('update users set is_active = false where id = $1', [current.user_id]);

    await audit(client, {
      actorUserId: auth.userId, actorEmail: auth.email, actorRole: 'HOD',
      action: 'ADVISOR_REMOVED', entityType: 'staff', entityId: staffId,
      details: {
        name: current.name,
        email: current.email,
        studentsToReassign: affected.length,
      },
    });
  });

  // Tell them directly rather than leaving it to be discovered.
  for (const student of affected) {
    const row = await one(
      'select user_id from students where register_number = $1', [student.register_number]
    );
    if (!row) continue;
    await notify(null, row.user_id, {
      title: 'Choose your class again',
      body: `${current.name} is no longer your class advisor. Open your profile and `
        + 'pick your class so your next OD reaches the right person.',
      category: 'CLASS_CHANGED',
    });
  }

  return {
    ...(await advisorRoster(auth)),
    releasedClasses: [...new Set(affected.map((a) => `Year ${a.year} Section ${a.section}`))],
    studentsToReassign: affected.map((a) => ({
      name: a.name, registerNumber: a.register_number,
    })),
  };
}

// ---------------------------------------------------------------------------
// OD workflow
// ---------------------------------------------------------------------------

const REQUEST_COLUMNS = `
  r.id, r.reference_no, r.event_type, r.event_name, r.event_date, r.event_day,
  r.event_end_date, r.day_count,
  r.description, r.submission_type, r.status, r.advisor_remarks, r.hod_remarks,
  r.advisor_decided_at, r.hod_decided_at, r.created_at,
  s.name as student_name, s.register_number, s.email as student_email,
  s.year, s.section,
  st.name as advisor_name, st.email as advisor_email,
  res.status as result_status, res.project_name, res.prize, res.prize_details,
  res.description as result_description`;

const REQUEST_JOINS = `
  from od_requests r
  join students s on s.id = r.student_id
  join staff st on st.id = r.advisor_staff_id
  left join od_results res on res.od_request_id = r.id`;

const FILE_LABEL = {
  CERTIFICATE: 'the certificate',
  WINNING_PHOTO: 'the prize photo',
  EVENT_PHOTO: 'a photo from the event',
  SUPPORTING_DOCUMENT: 'a supporting document',
};

/// The evidence a result has to be backed by. A supporting document stays
/// optional - it is the one attachment that is not always relevant.
function requiredEvidence(status) {
  return status === 'WON'
    ? ['CERTIFICATE', 'EVENT_PHOTO', 'WINNING_PHOTO']
    : ['CERTIFICATE', 'EVENT_PHOTO'];
}

/// "on 12 Mar 2026" or "from 12 Mar to 14 Mar 2026", for notification text.
function describeDates(from, to) {
  const fmt = (d) => new Date(`${d}T00:00:00Z`).toLocaleDateString('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC',
  });
  if (!to || to === from) return `on ${fmt(from)}`;
  return `from ${fmt(from)} to ${fmt(to)}`;
}

const dateText = (v) => {
  if (!v) return null;
  return v instanceof Date ? v.toISOString().slice(0, 10) : String(v).slice(0, 10);
};

async function hydrate(rows) {
  if (!rows.length) return [];
  const ids = rows.map((r) => r.id);
  const members = await query(
    `select id, od_request_id, member_name, register_number, contribution
       from od_team_members where od_request_id = any($1) order by position`,
    [ids]
  );
  const files = await query(
    'select od_request_id, id, kind, object_key, file_name, mime_type, size_bytes from result_files where od_request_id = any($1)',
    [ids]
  );
  return rows.map((r) => ({
    id: r.id,
    referenceNo: r.reference_no,
    studentName: r.student_name,
    studentEmail: r.student_email,
    registerNumber: r.register_number,
    year: r.year,
    section: r.section,
    department: 'Information Technology',
    advisorName: r.advisor_name,
    advisorEmail: r.advisor_email,
    submissionType: r.submission_type,
    // Names on their own, because most screens only list them, and the full
    // people for the result screen and the reports, which need who did what.
    teamMembers: members.filter((m) => m.od_request_id === r.id).map((m) => m.member_name),
    team: members
      .filter((m) => m.od_request_id === r.id)
      .map((m) => ({
        id: m.id,
        name: m.member_name,
        registerNumber: m.register_number,
        contribution: m.contribution,
      })),
    eventType: r.event_type,
    eventName: r.event_name,
    eventDate: dateText(r.event_date),
    eventEndDate: dateText(r.event_end_date) || dateText(r.event_date),
    dayCount: r.day_count || 1,
    eventDay: r.event_day,
    description: r.description,
    status: r.status,
    advisorRemarks: r.advisor_remarks,
    hodRemarks: r.hod_remarks,
    advisorTimestamp: r.advisor_decided_at,
    hodTimestamp: r.hod_decided_at,
    createdAt: r.created_at,
    resultStatus: r.result_status || 'PENDING',
    resultProjectName: r.project_name,
    resultPrize: r.prize,
    resultPrizeDetails: r.prize_details,
    resultDescription: r.result_description,
    files: files.filter((f) => f.od_request_id === r.id).map((f) => ({
      id: f.id, kind: f.kind, objectKey: f.object_key, fileName: f.file_name,
      mimeType: f.mime_type, sizeBytes: Number(f.size_bytes),
    })),
  }));
}

/// Turns one audit row into a sentence.
///
/// The HOD reads this screen to know what has been happening in the
/// department, so it says "Aravind won First place at CodeFest" rather than
/// RESULT_SUBMITTED and a blob of JSON.
function auditSentence(a) {
  const who = a.actor_name || a.actor_email || 'Someone';
  const d = (typeof a.details === 'string' ? safeJson(a.details) : a.details) || {};
  const event = a.event_name || d.event || 'an event';
  const at = a.event_name || d.event ? ` for ${event}` : '';

  switch (a.action) {
    case 'OD_CREATED': {
      const when = d.from && d.to && d.from !== d.to
        ? ` (${d.days} days)`
        : '';
      return `${who} applied for an OD for ${event}${when}`;
    }
    case 'ADVISOR_APPROVED':
      return `${who} recommended ${event} and sent it to the HOD`;
    case 'ADVISOR_REJECTED':
      return `${who} did not recommend ${event}`;
    case 'HOD_APPROVED':
      return `${who} sanctioned the OD for ${event}`;
    case 'HOD_REJECTED':
      return `${who} did not sanction the OD for ${event}`;
    case 'RESULT_SUBMITTED':
      return d.status === 'WON'
        ? `${who} won ${d.prize || 'a prize'} at ${event}`
        : `${who} took part in ${event}`;
    case 'FILE_UPLOADED':
      return `${who} attached ${FILE_LABEL[d.kind] || 'a file'}${at}`;
    case 'FILE_DELETED':
      return `${who} removed an attachment${at}`;
    case 'PROFILE_COMPLETED':
      return `${who} joined Year ${d.year} Section ${d.section}`;
    case 'CLASS_CHANGED':
      return `${who} moved to Year ${d.year} Section ${d.section}`;
    case 'DEVICE_REGISTERED':
      return `${who} signed in on a new device`;
    default:
      return `${who} - ${String(a.action).replace(/_/g, ' ').toLowerCase()}`;
  }
}

function safeJson(v) {
  try {
    return JSON.parse(v);
  } catch {
    return {};
  }
}

/// Everything the caller is allowed to see. Scoping happens in SQL, so a
/// client cannot widen it.
async function sync(auth, p) {
  const limit = Math.min(Number(p?.limit) || 100, 300);
  let rows;

  if (auth.role === 'STUDENT') {
    rows = await query(
      `select ${REQUEST_COLUMNS} ${REQUEST_JOINS}
        where r.student_id = $1 order by r.created_at desc limit $2`,
      [auth.studentId, limit]
    );
  } else if (auth.role === 'ADVISOR') {
    rows = await query(
      `select ${REQUEST_COLUMNS} ${REQUEST_JOINS}
        where r.advisor_staff_id = $1 order by r.created_at desc limit $2`,
      [auth.staffId, limit]
    );
  } else {
    rows = await query(
      `select ${REQUEST_COLUMNS} ${REQUEST_JOINS} order by r.created_at desc limit $1`,
      [limit]
    );
  }

  const notifications = await query(
    `select id, title, body, category, is_read, created_at
       from notifications where user_id = $1 order by created_at desc limit 40`,
    [auth.userId]
  );

  const auditLogs = auth.role === 'HOD'
    ? await query(
        `select a.id, a.action, a.entity_type, a.entity_id, a.actor_email,
                a.actor_role, a.details, a.created_at,
                coalesce(st.name, s.name, u.display_name,
                         split_part(a.actor_email, '@', 1)) as actor_name,
                r.event_name, r.reference_no
           from audit_logs a
           left join users u on u.id = a.actor_user_id
           left join students s on s.user_id = a.actor_user_id
           left join staff st on st.user_id = a.actor_user_id
           left join od_requests r
                  on a.entity_type = 'od_request' and r.id = a.entity_id
          order by a.created_at desc limit 200`
      )
    : [];

  return {
    success: true,
    data: {
      requests: await hydrate(rows),
      notifications: notifications.map((n) => ({
        id: n.id, title: n.title, text: n.body, category: n.category,
        isRead: n.is_read, time: n.created_at,
      })),
      auditLogs: auditLogs.map((a) => ({
        id: a.id,
        action: a.action,
        actor: a.actor_email,
        actorName: a.actor_name,
        role: a.actor_role,
        // A sentence, because the HOD reads this to know what happened, not
        // to decode it. The raw details stay available underneath.
        summary: auditSentence(a),
        details: typeof a.details === 'string' ? a.details : JSON.stringify(a.details || {}),
        requestId: a.entity_id,
        time: a.created_at,
      })),
    },
  };
}

async function createOd(auth, p) {
  requireRole(auth, 'STUDENT');
  if (!auth.studentId) throw new HttpError(409, 'Complete your profile before raising an OD.');

  const student = await one(
    `select s.id, s.name, s.register_number, s.class_assignment_id, c.staff_id
       from students s
       left join class_assignments c
              on c.id = s.class_assignment_id and c.is_active
       left join staff st on st.id = c.staff_id and st.is_active
      where s.id = $1 and st.id is not null`,
    [auth.studentId]
  );
  if (!student?.staff_id) {
    throw new HttpError(409,
      'Your class advisor has changed. Open your profile and choose your class '
      + 'again before raising an OD.');
  }

  const submissionType = p.submissionType === 'TEAM' ? 'TEAM' : 'SOLO';
  const eventDate = dateOf(p.eventDate, 'Event date');

  // The app sends a start date and how many days it runs; the end date is
  // derived from those so the two can never disagree. An older client that
  // sends neither is treated as the one-day request it means.
  const dayCount = Math.min(Math.max(Number(p.dayCount) || 1, 1), 30);
  let eventEndDate = p.eventEndDate ? dateOf(p.eventEndDate, 'Last day') : null;
  if (!eventEndDate) {
    const end = new Date(`${eventDate}T00:00:00Z`);
    end.setUTCDate(end.getUTCDate() + dayCount - 1);
    eventEndDate = end.toISOString().slice(0, 10);
  }
  if (eventEndDate < eventDate) {
    throw new HttpError(400, 'The last day cannot be before the first day.');
  }
  const members = submissionType === 'TEAM' && Array.isArray(p.teamMembers)
    ? p.teamMembers.map((m) => clean(m).slice(0, 80)).filter(Boolean).slice(0, 5)
    : [];

  const created = await transaction(async (client) => {
    const { rows } = await client.query(
      `insert into od_requests (student_id, advisor_staff_id, class_assignment_id,
                                event_type, event_name, event_date, event_end_date,
                                day_count, event_day, description, submission_type)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) returning id, reference_no`,
      [student.id, student.staff_id, student.class_assignment_id,
       text(p.eventType, 'Event type', 40), text(p.eventName, 'Event name', 120),
       eventDate, eventEndDate, dayCount,
       clean(p.eventDay).slice(0, 12), text(p.description, 'Description', 1000),
       submissionType]
    );
    const req = rows[0];
    for (let i = 0; i < members.length; i += 1) {
      await client.query(
        'insert into od_team_members (od_request_id, member_name, position) values ($1, $2, $3)',
        [req.id, members[i], i]
      );
    }
    await audit(client, {
      actorUserId: auth.userId, actorEmail: auth.email, actorRole: 'STUDENT',
      action: 'OD_CREATED', entityType: 'od_request', entityId: req.id,
      details: {
        reference: req.reference_no,
        event: clean(p.eventName),
        days: dayCount,
        from: eventDate,
        to: eventEndDate,
      },
    });
    return req;
  });

  // The advisor is told there is something to review; the HOD is told it
  // exists but is not actionable yet.
  const advisorUser = await one('select user_id from staff where id = $1', [student.staff_id]);
  if (advisorUser) {
    await notify(null, advisorUser.user_id, {
      title: 'New OD request',
      body: `${student.name} (${student.register_number}) - ${clean(p.eventName)}, ${describeDates(eventDate, eventEndDate)}`,
      odRequestId: created.id, category: 'OD_CREATED',
    });
  }
  for (const uid of await hodUserIds()) {
    await notify(null, uid, {
      title: 'OD request submitted',
      body: `${student.name} - ${clean(p.eventName)}. Waiting for Class Advisor approval.`,
      odRequestId: created.id, category: 'OD_CREATED',
    });
  }

  const rows = await query(`select ${REQUEST_COLUMNS} ${REQUEST_JOINS} where r.id = $1`, [created.id]);
  return { success: true, request: (await hydrate(rows))[0] };
}

async function advisorDecide(auth, p) {
  requireRole(auth, 'ADVISOR');
  const req = await requestForActor(auth, p.reqId ?? p.requestId);
  if (req.status !== 'PENDING_ADVISOR') throw new HttpError(409, 'This request was already reviewed.');

  const approve = p.approve === true;
  const remarks = clean(p.remarks).slice(0, 500)
    || (approve ? 'Recommended by Class Advisor.' : 'Not approved by Class Advisor.');
  const status = approve ? 'APPROVED_BY_ADVISOR' : 'REJECTED_ADVISOR';

  await transaction(async (client) => {
    await client.query(
      'update od_requests set status = $1, advisor_remarks = $2, advisor_decided_at = now() where id = $3',
      [status, remarks, req.id]
    );
    await client.query(
      `insert into od_approvals (od_request_id, step, decision, decided_by, remarks)
       values ($1, 'ADVISOR', $2, $3, $4)`,
      [req.id, approve ? 'APPROVED' : 'REJECTED', auth.staffId, remarks]
    );
    await audit(client, {
      actorUserId: auth.userId, actorEmail: auth.email, actorRole: 'ADVISOR',
      action: approve ? 'ADVISOR_APPROVED' : 'ADVISOR_REJECTED',
      entityType: 'od_request', entityId: req.id, details: { remarks },
    });
  });

  const student = await one(
    'select u.id as user_id, s.name from students s join users u on u.id = s.user_id where s.id = $1',
    [req.student_id]
  );
  await notify(null, student.user_id, {
    title: approve ? 'Advisor approved your OD' : 'Advisor rejected your OD',
    body: approve ? `${req.event_name}: forwarded to the HOD for final sanction.` : `${req.event_name}: ${remarks}`,
    odRequestId: req.id, category: status,
  });
  if (approve) {
    for (const uid of await hodUserIds()) {
      await notify(null, uid, {
        title: 'OD ready for HOD review',
        body: `${student.name} - ${req.event_name}. Recommended by ${auth.name}.`,
        odRequestId: req.id, category: 'HOD_ACTIONABLE',
      });
    }
  }

  const rows = await query(`select ${REQUEST_COLUMNS} ${REQUEST_JOINS} where r.id = $1`, [req.id]);
  return { success: true, request: (await hydrate(rows))[0] };
}

async function hodDecide(auth, p) {
  requireRole(auth, 'HOD');
  const req = await requestForActor(auth, p.reqId ?? p.requestId);
  if (req.status !== 'APPROVED_BY_ADVISOR') {
    throw new HttpError(409, 'Waiting for Class Advisor approval.');
  }

  const approve = p.approve === true;
  const remarks = clean(p.remarks).slice(0, 500) || (approve ? 'Sanctioned by HOD.' : 'Not sanctioned by HOD.');
  const status = approve ? 'APPROVED' : 'REJECTED_HOD';

  await transaction(async (client) => {
    await client.query(
      'update od_requests set status = $1, hod_remarks = $2, hod_decided_at = now() where id = $3',
      [status, remarks, req.id]
    );
    await client.query(
      `insert into od_approvals (od_request_id, step, decision, decided_by, remarks)
       values ($1, 'HOD', $2, $3, $4)`,
      [req.id, approve ? 'APPROVED' : 'REJECTED', auth.staffId, remarks]
    );
    await audit(client, {
      actorUserId: auth.userId, actorEmail: auth.email, actorRole: 'HOD',
      action: approve ? 'HOD_APPROVED' : 'HOD_REJECTED',
      entityType: 'od_request', entityId: req.id, details: { remarks },
    });
  });

  const student = await one(
    'select u.id as user_id, s.name from students s join users u on u.id = s.user_id where s.id = $1',
    [req.student_id]
  );
  await notify(null, student.user_id, {
    title: approve ? 'OD sanctioned by HOD' : 'OD rejected by HOD',
    body: approve
      ? `${req.event_name}: approved. You can submit your result once the event is over.`
      : `${req.event_name}: ${remarks}`,
    odRequestId: req.id, category: status,
  });
  const advisorUser = await one('select user_id from staff where id = $1', [req.advisor_staff_id]);
  if (advisorUser) {
    await notify(null, advisorUser.user_id, {
      title: approve ? 'OD sanctioned' : 'OD rejected by HOD',
      body: `${student.name} - ${req.event_name}`,
      odRequestId: req.id, category: status,
    });
  }

  const rows = await query(`select ${REQUEST_COLUMNS} ${REQUEST_JOINS} where r.id = $1`, [req.id]);
  return { success: true, request: (await hydrate(rows))[0] };
}

async function submitResult(auth, p) {
  requireRole(auth, 'STUDENT');
  const req = await requestForActor(auth, p.reqId ?? p.requestId);
  if (req.status !== 'APPROVED') {
    throw new HttpError(409, 'Results can be added only after the OD is approved.');
  }

  const status = p.status === 'WON' ? 'WON' : 'PARTICIPATED';
  const prize = clean(p.prize).slice(0, 80);
  if (status === 'WON' && !prize) throw new HttpError(400, 'Tell us which prize you won.');

  // The result is a claim; the attachments are what backs it. The app blocks
  // the button, and this is why the block cannot be worked around.
  const attached = await query(
    'select distinct kind from result_files where od_request_id = $1', [req.id]
  );
  const have = new Set(attached.map((f) => f.kind));
  const missing = requiredEvidence(status).filter((k) => !have.has(k));
  if (missing.length) {
    const names = missing.map((k) => FILE_LABEL[k]);
    const list = names.length === 1
      ? names[0]
      : `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`;
    throw new HttpError(409, `Attach ${list} before submitting the result.`);
  }

  // A team result credits people. Every member needs their own contribution,
  // supplied now or already recorded.
  const team = await query(
    'select id, member_name, contribution from od_team_members where od_request_id = $1 order by position',
    [req.id]
  );
  const contributions = new Map();
  if (req.submission_type === 'TEAM' && team.length) {
    const sent = Array.isArray(p.teamContributions) ? p.teamContributions : [];
    for (const member of team) {
      const match = sent.find(
        (c) => c && (c.id === member.id || clean(c.name) === member.member_name)
      );
      const value = clean(match?.contribution).slice(0, 400) || clean(member.contribution);
      if (!value) {
        throw new HttpError(400, `Tell us what ${member.member_name} contributed.`);
      }
      contributions.set(member.id, value);
    }
  }

  await transaction(async (client) => {
    await client.query(
      `insert into od_results (od_request_id, status, project_name, prize, prize_details, description)
       values ($1, $2, $3, $4, $5, $6)
       on conflict (od_request_id) do update
         set status = excluded.status, project_name = excluded.project_name,
             prize = excluded.prize, prize_details = excluded.prize_details,
             description = excluded.description`,
      [req.id, status, clean(p.projectName).slice(0, 120) || req.event_name,
       prize || null, clean(p.prizeDetails).slice(0, 300) || null,
       clean(p.description).slice(0, 1000) || null]
    );
    await audit(client, {
      actorUserId: auth.userId, actorEmail: auth.email, actorRole: 'STUDENT',
      action: 'RESULT_SUBMITTED', entityType: 'od_request', entityId: req.id,
      details: {
        status,
        prize,
        project: clean(p.projectName).slice(0, 120) || req.event_name,
      },
    });

    for (const [id, value] of contributions) {
      await client.query('update od_team_members set contribution = $1 where id = $2',
        [value, id]);
    }
  });

  const advisorUser = await one('select user_id from staff where id = $1', [req.advisor_staff_id]);
  if (advisorUser) {
    await notify(null, advisorUser.user_id, {
      title: status === 'WON' ? 'Student won an event' : 'Result submitted',
      body: `${req.event_name}: ${status}${prize ? ` - ${prize}` : ''}`,
      odRequestId: req.id, category: 'RESULT',
    });
  }

  const rows = await query(`select ${REQUEST_COLUMNS} ${REQUEST_JOINS} where r.id = $1`, [req.id]);
  return { success: true, request: (await hydrate(rows))[0] };
}

async function registerDevice(auth, p) {
  const token = clean(p.fcmToken);
  if (!token) throw new HttpError(400, 'No device token supplied.');
  // A token identifies a device, so clear it from anyone else who had it -
  // otherwise a shared phone keeps receiving the previous user's notifications.
  await query('update users set fcm_token = null where fcm_token = $1 and id <> $2', [token, auth.userId]);
  await query('update users set fcm_token = $1 where id = $2', [token, auth.userId]);
  return { success: true };
}

async function markNotificationsRead(auth) {
  await query('update notifications set is_read = true where user_id = $1 and not is_read', [auth.userId]);
  return { success: true };
}

// ---------------------------------------------------------------------------
// Files
// ---------------------------------------------------------------------------

/// Attaches a certificate or photo to an OD.
///
/// The bytes arrive base64 encoded, already compressed by the app. They are
/// checked again here - a client can claim anything - and the caller must own
/// the request and it must be approved, so a file cannot be attached to
/// someone else's OD, or to one that was never sanctioned.
async function uploadFile(auth, p) {
  requireRole(auth, 'STUDENT');
  if (!storageConfigured()) {
    throw new HttpError(503, 'File uploads are not configured on the server yet.');
  }

  const req = await requestForActor(auth, p.reqId ?? p.requestId);
  if (req.status !== 'APPROVED') {
    throw new HttpError(409, 'Files can be attached only after the OD is approved.');
  }

  const kind = clean(p.kind).toUpperCase();
  if (!['CERTIFICATE', 'WINNING_PHOTO', 'EVENT_PHOTO', 'SUPPORTING_DOCUMENT'].includes(kind)) {
    throw new HttpError(400, 'Unknown file type.');
  }

  const mimeType = clean(p.mimeType).toLowerCase();
  if (!ALLOWED_MIME.includes(mimeType)) {
    throw new HttpError(400, 'Only JPEG, PNG, WebP images or PDF files can be uploaded.');
  }

  const base64 = String(p.data || '').replace(/^data:[^;]+;base64,/, '');
  if (!base64) throw new HttpError(400, 'No file contents were sent.');

  let bytes;
  try {
    bytes = Buffer.from(base64, 'base64');
  } catch {
    throw new HttpError(400, 'The file could not be read.');
  }
  if (bytes.length === 0) throw new HttpError(400, 'The file is empty.');
  if (bytes.length > MAX_BYTES) {
    throw new HttpError(413, 'That file is larger than 10 MB even after compression.');
  }

  const result = await one('select id from od_results where od_request_id = $1', [req.id]);
  const objectKey = objectKeyFor({ odRequestId: req.id, kind, mimeType });
  await uploadObject({ objectKey, bytes, mimeType });

  let row;
  try {
    row = await one(
      `insert into result_files (od_result_id, od_request_id, kind, object_key,
                                 file_name, mime_type, size_bytes, uploaded_by)
       values ($1, $2, $3, $4, $5, $6, $7, $8)
       returning id, kind, object_key, file_name, mime_type, size_bytes`,
      [result?.id || null, req.id, kind, objectKey,
       text(p.fileName, 'File name', 120), mimeType, bytes.length, auth.userId]
    );
  } catch (err) {
    // Do not leave an orphan in storage if the row could not be written.
    await deleteObject(objectKey);
    throw err;
  }

  await audit(null, {
    actorUserId: auth.userId, actorEmail: auth.email, actorRole: 'STUDENT',
    action: 'FILE_UPLOADED', entityType: 'od_request', entityId: req.id,
    details: { kind, fileName: row.file_name, sizeBytes: bytes.length },
  });

  return {
    success: true,
    file: {
      id: row.id,
      kind: row.kind,
      objectKey: row.object_key,
      fileName: row.file_name,
      mimeType: row.mime_type,
      sizeBytes: Number(row.size_bytes),
    },
  };
}

/// A short-lived URL for viewing one attached file.
///
/// The caller must be allowed to see the request it belongs to, which is the
/// same check used everywhere else: a student sees their own, an advisor their
/// class's, the HOD the department's.
async function fileUrl(auth, p) {
  if (!storageConfigured()) {
    throw new HttpError(503, 'File storage is not configured on the server yet.');
  }
  const file = await one(
    'select id, od_request_id, object_key, file_name, mime_type from result_files where id = $1',
    [uuidOf(p.fileId, 'No file was specified.')]
  );
  if (!file) throw new HttpError(404, 'File not found.');

  await requestForActor(auth, file.od_request_id);

  return {
    success: true,
    url: await signedUrl(file.object_key),
    fileName: file.file_name,
    mimeType: file.mime_type,
    expiresInSeconds: 300,
  };
}

/// Removes a file the student attached.
async function deleteFile(auth, p) {
  requireRole(auth, 'STUDENT');
  const file = await one(
    'select id, od_request_id, object_key from result_files where id = $1',
    [uuidOf(p.fileId, 'No file was specified.')]
  );
  if (!file) throw new HttpError(404, 'File not found.');
  await requestForActor(auth, file.od_request_id);

  await query('delete from result_files where id = $1', [file.id]);
  await deleteObject(file.object_key);
  await audit(null, {
    actorUserId: auth.userId, actorEmail: auth.email, actorRole: 'STUDENT',
    action: 'FILE_DELETED', entityType: 'od_request', entityId: file.od_request_id,
  });
  return { success: true };
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

export async function OPTIONS() {
  return json({});
}

export async function POST(req) {
  try {
    const body = await req.json().catch(() => ({}));
    const action = clean(body.action);
    const p = body.payload || {};

    // Public: needed before anyone has an account.
    if (action === 'CLASSES' || action === 'ADVISORS') return json(await classList());

    // Staff password sign-in returns the same session shape as a Firebase one.
    if (action === 'PASSWORD_LOGIN') {
      const auth = await passwordIdentify({ email: p.email, password: p.password });
      await audit(null, {
        actorUserId: auth.userId, actorEmail: auth.email, actorRole: auth.role,
        action: 'PASSWORD_LOGIN', entityType: 'user', entityId: auth.userId,
      });
      // Staff have no Firebase account, so they carry a signed token instead.
      return json({ ...(await session(auth)), token: signStaffToken(auth) });
    }

    const auth = await identify(req);

    switch (action) {
      case 'SESSION': {
        const res = await session(auth);
        // A staff session slides: whenever it is getting on, hand back a
        // fresh token. The app saves it, so someone who keeps using the app
        // never has to type the password again.
        return json(auth.renewToken ? { ...res, token: signStaffToken(auth) } : res);
      }
      case 'REGISTER':         return json(await registerStudent(auth, p));
      case 'CHANGE_CLASS':     return json(await changeClass(auth, p));
      case 'SYNC':             return json(await sync(auth, p));
      case 'CREATE_OD':        return json(await createOd(auth, p));
      case 'ADVISOR_DECIDE':   return json(await advisorDecide(auth, p));
      case 'HOD_DECIDE':       return json(await hodDecide(auth, p));
      case 'SUBMIT_RESULT':    return json(await submitResult(auth, p));
      case 'REGISTER_DEVICE':  return json(await registerDevice(auth, p));
      case 'ADVISOR_ROSTER':   return json(await advisorRoster(auth));
      case 'ADVISOR_CREATE':   return json(await createAdvisor(auth, p));
      case 'ADVISOR_UPDATE':   return json(await updateAdvisor(auth, p));
      case 'ADVISOR_REMOVE':   return json(await removeAdvisor(auth, p));
      case 'MARK_READ':        return json(await markNotificationsRead(auth));
      case 'UPLOAD_FILE':      return json(await uploadFile(auth, p));
      case 'FILE_URL':         return json(await fileUrl(auth, p));
      case 'DELETE_FILE':      return json(await deleteFile(auth, p));
      default:
        return json({ success: false, error: 'Unknown action.' }, 400);
    }
  } catch (err) {
    const status = err instanceof HttpError ? err.status : 500;
    if (status === 500) console.error('api v2 error:', err);
    return json(
      { success: false, error: status === 500 ? 'Server error. Please try again.' : err.message },
      status
    );
  }
}
