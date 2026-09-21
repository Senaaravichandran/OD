-- SMVEC IT Department - OD Management
-- Initial schema.
--
-- Design notes
--   * Identity comes from Firebase. `users.firebase_uid` is the link; there are
--     no passwords for students here at all.
--   * Staff are not self-service. `staff` is seeded from the department roster
--     and `class_assignments` decides who advises which class, so a student's
--     advisor is derived, never chosen.
--   * Files live in Supabase Storage. Only the object key and metadata are
--     stored here, never the bytes.
--   * Every state change lands in `audit_logs`, which nothing but the service
--     role may write.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type user_role as enum ('STUDENT', 'ADVISOR', 'HOD');

create type od_status as enum (
  'PENDING_ADVISOR',      -- waiting on the class advisor
  'APPROVED_BY_ADVISOR',  -- recommended, waiting on the HOD
  'REJECTED_ADVISOR',     -- advisor said no; terminal
  'APPROVED',             -- sanctioned by the HOD; terminal
  'REJECTED_HOD'          -- HOD said no; terminal
);

create type result_status as enum ('PENDING', 'PARTICIPATED', 'WON');

create type submission_type as enum ('SOLO', 'TEAM');

create type approval_step as enum ('ADVISOR', 'HOD');

create type approval_decision as enum ('APPROVED', 'REJECTED');

create type file_kind as enum (
  'CERTIFICATE',
  'WINNING_PHOTO',
  'EVENT_PHOTO',
  'SUPPORTING_DOCUMENT'
);

-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------

create table users (
  id            uuid primary key default gen_random_uuid(),
  firebase_uid  text unique,                  -- null for staff who sign in by password
  email         text not null unique,
  role          user_role not null,
  display_name  text not null,
  photo_url     text,
  fcm_token     text,                         -- current device token for push
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  last_login_at timestamptz,
  constraint users_email_lowercase check (email = lower(email))
);

create index users_role_idx on users (role);
create index users_firebase_uid_idx on users (firebase_uid) where firebase_uid is not null;

-- ---------------------------------------------------------------------------
-- Department structure
-- ---------------------------------------------------------------------------

create table staff (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null unique references users (id) on delete cascade,
  name         text not null,
  email        text not null unique,
  department   text not null default 'Information Technology',
  -- Argon2/bcrypt digest. Never a plaintext password, never returned by the API.
  password_hash text,
  is_hod       boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint staff_email_lowercase check (email = lower(email))
);

create index staff_is_hod_idx on staff (is_hod) where is_hod;

-- Which staff member advises which class. A class has exactly one advisor; an
-- advisor may hold more than one class.
create table class_assignments (
  id          uuid primary key default gen_random_uuid(),
  staff_id    uuid not null references staff (id) on delete restrict,
  year        smallint not null,
  section     text not null,
  batch       text,                            -- e.g. 2023-2027
  academic_year text,                          -- e.g. 2026-2027
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  constraint class_year_range check (year between 1 and 4),
  constraint class_section_format check (section ~ '^[A-F]$')
);

-- One active advisor per class.
create unique index class_assignments_unique_active
  on class_assignments (year, section)
  where is_active;

create index class_assignments_staff_idx on class_assignments (staff_id);

-- ---------------------------------------------------------------------------
-- Students
-- ---------------------------------------------------------------------------

create table students (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null unique references users (id) on delete cascade,
  register_number     text not null unique,
  name                text not null,
  email               text not null unique,
  year                smallint not null,
  section             text not null,
  department          text not null default 'Information Technology',
  -- Denormalised on purpose: the advisor a student is attached to is resolved
  -- from their class at registration and pinned here, so historical requests
  -- keep pointing at the right person even if the roster changes later.
  class_assignment_id uuid references class_assignments (id) on delete set null,
  profile_completed   boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint students_year_range check (year between 1 and 4),
  constraint students_section_format check (section ~ '^[A-F]$'),
  constraint students_email_lowercase check (email = lower(email))
);

create index students_class_idx on students (year, section);
create index students_class_assignment_idx on students (class_assignment_id);

-- ---------------------------------------------------------------------------
-- Events and OD requests
-- ---------------------------------------------------------------------------

create table events (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  event_type  text not null,   -- Hackathon, Internship, Paper Presentation, ...
  event_date  date not null,
  venue       text,
  created_at  timestamptz not null default now()
);

create index events_type_idx on events (event_type);
create index events_date_idx on events (event_date desc);

create table od_requests (
  id                uuid primary key default gen_random_uuid(),
  reference_no      text not null unique,      -- human-facing, e.g. OD-2026-0001
  student_id        uuid not null references students (id) on delete cascade,
  -- Pinned at creation, not joined live, so a roster change never reroutes a
  -- request that is already in flight.
  advisor_staff_id  uuid not null references staff (id) on delete restrict,
  class_assignment_id uuid references class_assignments (id) on delete set null,
  event_id          uuid references events (id) on delete set null,

  event_type        text not null,
  event_name        text not null,
  event_date        date not null,
  event_day         text,
  description       text not null,
  submission_type   submission_type not null default 'SOLO',

  status            od_status not null default 'PENDING_ADVISOR',
  advisor_remarks   text,
  advisor_decided_at timestamptz,
  hod_remarks       text,
  hod_decided_at    timestamptz,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index od_requests_student_idx on od_requests (student_id, created_at desc);
create index od_requests_advisor_idx on od_requests (advisor_staff_id, status);
create index od_requests_status_idx on od_requests (status, created_at desc);
create index od_requests_event_type_idx on od_requests (event_type);
create index od_requests_event_date_idx on od_requests (event_date desc);

create table od_team_members (
  id            uuid primary key default gen_random_uuid(),
  od_request_id uuid not null references od_requests (id) on delete cascade,
  member_name   text not null,
  register_number text,
  student_id    uuid references students (id) on delete set null,
  position      smallint not null default 0,
  created_at    timestamptz not null default now()
);

create index od_team_members_request_idx on od_team_members (od_request_id);

-- Full decision history. The current state lives on od_requests; this is the
-- trail of how it got there, including a reversal if one ever happens.
create table od_approvals (
  id            uuid primary key default gen_random_uuid(),
  od_request_id uuid not null references od_requests (id) on delete cascade,
  step          approval_step not null,
  decision      approval_decision not null,
  decided_by    uuid not null references staff (id) on delete restrict,
  remarks       text,
  decided_at    timestamptz not null default now()
);

create index od_approvals_request_idx on od_approvals (od_request_id, decided_at);

-- ---------------------------------------------------------------------------
-- Results
-- ---------------------------------------------------------------------------

create table od_results (
  id            uuid primary key default gen_random_uuid(),
  od_request_id uuid not null unique references od_requests (id) on delete cascade,
  status        result_status not null default 'PENDING',
  project_name  text,
  prize         text,                 -- '1st Prize', 'Runner Up', ...
  prize_details text,
  description   text,
  submitted_at  timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  -- A win has to say what was won.
  constraint od_results_won_requires_prize
    check (status <> 'WON' or (prize is not null and length(trim(prize)) > 0))
);

-- Object keys in Supabase Storage. The bytes are never stored in Postgres.
create table result_files (
  id            uuid primary key default gen_random_uuid(),
  od_result_id  uuid references od_results (id) on delete cascade,
  od_request_id uuid not null references od_requests (id) on delete cascade,
  kind          file_kind not null,
  bucket        text not null default 'od-files',
  object_key    text not null unique,
  file_name     text not null,
  mime_type     text not null,
  size_bytes    bigint not null,
  width         integer,
  height        integer,
  uploaded_by   uuid references users (id) on delete set null,
  created_at    timestamptz not null default now(),
  constraint result_files_size_limit check (size_bytes > 0 and size_bytes <= 10485760),
  constraint result_files_mime_allowed
    check (mime_type in ('image/jpeg', 'image/png', 'image/webp', 'application/pdf'))
);

create index result_files_request_idx on result_files (od_request_id);
create index result_files_result_idx on result_files (od_result_id);

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------

create table notifications (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references users (id) on delete cascade,
  od_request_id uuid references od_requests (id) on delete cascade,
  title         text not null,
  body          text not null,
  category      text,
  is_read       boolean not null default false,
  pushed_at     timestamptz,       -- when FCM accepted it, null if not sent
  created_at    timestamptz not null default now()
);

create index notifications_user_idx on notifications (user_id, created_at desc);
create index notifications_unread_idx on notifications (user_id) where not is_read;

-- ---------------------------------------------------------------------------
-- Audit
-- ---------------------------------------------------------------------------

create table audit_logs (
  id            uuid primary key default gen_random_uuid(),
  actor_user_id uuid references users (id) on delete set null,
  actor_email   text,              -- kept even if the user is later removed
  actor_role    user_role,
  action        text not null,     -- OD_CREATED, ADVISOR_APPROVED, FILE_UPLOADED, ...
  entity_type   text not null,     -- od_request, student, staff, result, file
  entity_id     uuid,
  details       jsonb,
  ip_address    inet,
  created_at    timestamptz not null default now()
);

create index audit_logs_entity_idx on audit_logs (entity_type, entity_id, created_at desc);
create index audit_logs_actor_idx on audit_logs (actor_user_id, created_at desc);
create index audit_logs_action_idx on audit_logs (action, created_at desc);
create index audit_logs_created_idx on audit_logs (created_at desc);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger users_updated_at before update on users
  for each row execute function set_updated_at();
create trigger staff_updated_at before update on staff
  for each row execute function set_updated_at();
create trigger students_updated_at before update on students
  for each row execute function set_updated_at();
create trigger od_requests_updated_at before update on od_requests
  for each row execute function set_updated_at();
create trigger od_results_updated_at before update on od_results
  for each row execute function set_updated_at();

-- Human-readable OD reference: OD-<year>-<zero padded counter>.
create sequence od_reference_seq;

create or replace function next_od_reference()
returns text
language sql
as $$
  select 'OD-' || to_char(now(), 'YYYY') || '-' ||
         lpad(nextval('od_reference_seq')::text, 4, '0');
$$;

alter table od_requests
  alter column reference_no set default next_od_reference();

-- The HOD cannot act before the advisor has recommended. Enforced here as well
-- as in the API, so no code path can skip the step.
create or replace function enforce_od_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status <> 'PENDING_ADVISOR'
     and new.status in ('APPROVED_BY_ADVISOR', 'REJECTED_ADVISOR') then
    raise exception 'advisor decision is only valid while the request is pending advisor review (was %)', old.status;
  end if;

  if new.status in ('APPROVED', 'REJECTED_HOD')
     and old.status <> 'APPROVED_BY_ADVISOR' then
    raise exception 'HOD decision requires advisor approval first (was %)', old.status;
  end if;

  if old.status in ('APPROVED', 'REJECTED_HOD', 'REJECTED_ADVISOR') then
    raise exception 'request is already closed (%), it cannot change again', old.status;
  end if;

  return new;
end;
$$;

create trigger od_requests_transition before update of status on od_requests
  for each row execute function enforce_od_transition();

-- A result may only be recorded once the OD is actually approved.
create or replace function enforce_result_requires_approval()
returns trigger
language plpgsql
as $$
declare
  req_status od_status;
begin
  select status into req_status from od_requests where id = new.od_request_id;
  if req_status <> 'APPROVED' then
    raise exception 'a result can only be recorded for an approved OD (status is %)', req_status;
  end if;
  return new;
end;
$$;

create trigger od_results_requires_approval before insert or update on od_results
  for each row execute function enforce_result_requires_approval();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------
-- The API talks to Postgres with the service role and does its own
-- authorisation, so RLS is enabled with no permissive policies: if the anon or
-- authenticated key ever leaks, it reads nothing.

alter table users             enable row level security;
alter table staff             enable row level security;
alter table class_assignments enable row level security;
alter table students          enable row level security;
alter table events            enable row level security;
alter table od_requests       enable row level security;
alter table od_team_members   enable row level security;
alter table od_approvals      enable row level security;
alter table od_results        enable row level security;
alter table result_files      enable row level security;
alter table notifications     enable row level security;
alter table audit_logs        enable row level security;

-- The one exception: the class list has to be readable before a student has an
-- account, so they can pick their year and section while registering. It
-- exposes only the department's published class structure.
create policy class_assignments_public_read on class_assignments
  for select to anon, authenticated using (is_active);

-- ---------------------------------------------------------------------------
-- Reporting views
-- ---------------------------------------------------------------------------

create view od_report_rows as
select
  r.id                as od_request_id,
  r.reference_no,
  s.register_number,
  s.name              as student_name,
  s.email             as student_email,
  s.year,
  s.section,
  st.name             as advisor_name,
  st.email            as advisor_email,
  r.event_type,
  r.event_name,
  r.event_date,
  r.submission_type,
  r.status,
  r.advisor_remarks,
  r.hod_remarks,
  coalesce(res.status, 'PENDING')::result_status as result_status,
  res.project_name,
  res.prize,
  (select count(*) from result_files f where f.od_request_id = r.id) as file_count,
  r.created_at
from od_requests r
join students s on s.id = r.student_id
join staff st   on st.id = r.advisor_staff_id
left join od_results res on res.od_request_id = r.id;

comment on view od_report_rows is
  'Flattened row per OD request, for the advisor and HOD report screens and the PDF/Excel/Word exports.';
