-- Three things the department asked for.
--
-- 1. An OD covers a stretch of days, not one. A symposium that runs Thursday
--    to Saturday was being filed as a single date, which left the advisor to
--    work out the rest from the description.
--
-- 2. When a team wins, the department needs to know who did what. Recognition
--    goes to people, not to a row, so each member carries their own
--    contribution.
--
-- 3. The HOD's password changes.

-- ---------------------------------------------------------------------------
-- An OD spans days
-- ---------------------------------------------------------------------------

alter table od_requests
  add column if not exists event_end_date date,
  add column if not exists day_count smallint;

-- Existing requests were single-day, so say that rather than leaving a hole.
update od_requests
   set event_end_date = coalesce(event_end_date, event_date),
       day_count      = coalesce(day_count, 1);

alter table od_requests
  alter column event_end_date set default null,
  add constraint od_requests_end_after_start
    check (event_end_date is null or event_end_date >= event_date),
  add constraint od_requests_day_count_sane
    check (day_count is null or (day_count between 1 and 30));

comment on column od_requests.event_end_date is
  'Last day the OD covers. Equal to event_date for a one-day event.';
comment on column od_requests.day_count is
  'How many days the OD covers, inclusive of both ends. Derived from the dates at creation and stored so a report does not have to recompute it.';

create index if not exists od_requests_date_range_idx
  on od_requests (event_date, event_end_date);

-- ---------------------------------------------------------------------------
-- What each team member actually did
-- ---------------------------------------------------------------------------

alter table od_team_members
  add column if not exists contribution text;

comment on column od_team_members.contribution is
  'What this member contributed, in their own words. Required for every member before a team result can be recorded - the department credits people, not rows.';

-- ---------------------------------------------------------------------------
-- The HOD's password
-- ---------------------------------------------------------------------------
-- bcrypt cost 12 of the new password. The plaintext is not in this file, in
-- the repository, or anywhere the application can read it.

update staff
   set password_hash = '$2b$12$3NivDq9D136Zw385Uwz2..YTlpdwiVIyRP90/8fmq86DE25oE9asW'
 where email = 'hodit@smvec.ac.in';

-- ---------------------------------------------------------------------------
-- The report view carries the new columns
-- ---------------------------------------------------------------------------

drop view if exists od_report_rows;

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
  r.event_end_date,
  r.day_count,
  r.submission_type,
  r.status,
  r.advisor_remarks,
  r.hod_remarks,
  coalesce(res.status, 'PENDING')::result_status as result_status,
  res.project_name,
  res.prize,
  res.description     as result_description,
  (select count(*) from result_files f where f.od_request_id = r.id) as file_count,
  r.created_at
from od_requests r
join students s on s.id = r.student_id
join staff st   on st.id = r.advisor_staff_id
left join od_results res on res.od_request_id = r.id;

comment on view od_report_rows is
  'Flattened row per OD request, for the advisor, HOD and student report screens and the PDF/Excel/Word exports.';
