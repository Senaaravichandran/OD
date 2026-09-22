// SMVEC OD API v2 - Firebase identity, Supabase Postgres storage.
//
// One POST endpoint taking { action, payload }, same shape the apps already
// use. Callers present a Firebase ID token; staff may instead exchange a
// password for one through PASSWORD_LOGIN.
//
// Every rule that matters is enforced here and again by database triggers, so
// no client and no future code path can approve out of order.

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
              st.name as advisor_name, st.email as advisor_email,
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
    return {
      success: true,
      user: publicUser(auth, {
        registerNumber: student.register_number,
        name: student.name,
        year: student.year,
        section: student.section,
        advisorName: student.advisor_display,
        advisorEmail: student.advisor_email,
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
// OD workflow
// ---------------------------------------------------------------------------

const REQUEST_COLUMNS = `
  r.id, r.reference_no, r.event_type, r.event_name, r.event_date, r.event_day,
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

async function hydrate(rows) {
  if (!rows.length) return [];
  const ids = rows.map((r) => r.id);
  const members = await query(
    'select od_request_id, member_name, register_number from od_team_members where od_request_id = any($1) order by position',
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
    teamMembers: members.filter((m) => m.od_request_id === r.id).map((m) => m.member_name),
    eventType: r.event_type,
    eventName: r.event_name,
    eventDate: r.event_date instanceof Date ? r.event_date.toISOString().slice(0, 10) : r.event_date,
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
        `select id, action, entity_type, entity_id, actor_email, actor_role, details, created_at
           from audit_logs order by created_at desc limit 200`
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
        id: a.id, action: a.action, actor: a.actor_email, role: a.actor_role,
        details: typeof a.details === 'string' ? a.details : JSON.stringify(a.details || {}),
        requestId: a.entity_id, time: a.created_at,
      })),
    },
  };
}

async function createOd(auth, p) {
  requireRole(auth, 'STUDENT');
  if (!auth.studentId) throw new HttpError(409, 'Complete your profile before raising an OD.');

  const student = await one(
    `select s.id, s.name, s.register_number, s.class_assignment_id, c.staff_id
       from students s left join class_assignments c on c.id = s.class_assignment_id
      where s.id = $1`,
    [auth.studentId]
  );
  if (!student?.staff_id) throw new HttpError(409, 'No class advisor is set on your profile.');

  const submissionType = p.submissionType === 'TEAM' ? 'TEAM' : 'SOLO';
  const eventDate = dateOf(p.eventDate, 'Event date');
  const members = submissionType === 'TEAM' && Array.isArray(p.teamMembers)
    ? p.teamMembers.map((m) => clean(m).slice(0, 80)).filter(Boolean).slice(0, 5)
    : [];

  const created = await transaction(async (client) => {
    const { rows } = await client.query(
      `insert into od_requests (student_id, advisor_staff_id, class_assignment_id,
                                event_type, event_name, event_date, event_day,
                                description, submission_type)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9) returning id, reference_no`,
      [student.id, student.staff_id, student.class_assignment_id,
       text(p.eventType, 'Event type', 40), text(p.eventName, 'Event name', 120),
       eventDate, clean(p.eventDay).slice(0, 12), text(p.description, 'Description', 1000),
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
      details: { reference: req.reference_no, event: p.eventName },
    });
    return req;
  });

  // The advisor is told there is something to review; the HOD is told it
  // exists but is not actionable yet.
  const advisorUser = await one('select user_id from staff where id = $1', [student.staff_id]);
  if (advisorUser) {
    await notify(null, advisorUser.user_id, {
      title: 'New OD request',
      body: `${student.name} (${student.register_number}) - ${clean(p.eventName)} on ${eventDate}`,
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
      details: { status, prize },
    });
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
      case 'SESSION':          return json(await session(auth));
      case 'REGISTER':         return json(await registerStudent(auth, p));
      case 'CHANGE_CLASS':     return json(await changeClass(auth, p));
      case 'SYNC':             return json(await sync(auth, p));
      case 'CREATE_OD':        return json(await createOd(auth, p));
      case 'ADVISOR_DECIDE':   return json(await advisorDecide(auth, p));
      case 'HOD_DECIDE':       return json(await hodDecide(auth, p));
      case 'SUBMIT_RESULT':    return json(await submitResult(auth, p));
      case 'REGISTER_DEVICE':  return json(await registerDevice(auth, p));
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
