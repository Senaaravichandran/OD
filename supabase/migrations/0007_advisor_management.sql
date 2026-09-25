-- The HOD manages the class advisors: adding one, correcting one, removing one.
--
-- Removing is the interesting case. A class advisor cannot simply be deleted:
-- od_requests pins the advisor who received it, and class_assignments points
-- at them too, both with "on delete restrict" - deliberately, because a
-- department's record of who approved what must not evaporate when somebody
-- leaves. So removal retires the advisor instead. Their history stays exactly
-- as it was, their classes are released, and the students in those classes are
-- asked to choose again.

alter table staff
  add column if not exists is_active boolean not null default true,
  add column if not exists retired_at timestamptz;

comment on column staff.is_active is
  'False once the HOD has removed this advisor. The row stays so past OD requests keep the advisor who actually received them; sign-in is refused and their classes are released.';
comment on column staff.retired_at is
  'When the advisor was removed, for the audit trail.';

create index if not exists staff_active_idx on staff (is_active) where is_active;

-- ---------------------------------------------------------------------------
-- Retiring an advisor releases their classes
-- ---------------------------------------------------------------------------
-- Done here rather than only in the API so the two can never disagree: an
-- advisor who is not active cannot be left holding a live class, which would
-- send new requests to somebody who can no longer sign in.

create or replace function release_classes_of_retired_advisor()
returns trigger
language plpgsql
as $$
begin
  if new.is_active = false and old.is_active = true then
    update class_assignments
       set is_active = false
     where staff_id = new.id and is_active;
  end if;
  return new;
end;
$$;

comment on function release_classes_of_retired_advisor is
  'A retired advisor holds no classes. The students left without one are asked to choose again the next time they open the app.';

drop trigger if exists staff_retirement_releases_classes on staff;

create trigger staff_retirement_releases_classes after update of is_active on staff
  for each row execute function release_classes_of_retired_advisor();

-- ---------------------------------------------------------------------------
-- An active class needs an active advisor
-- ---------------------------------------------------------------------------

create or replace function class_needs_active_advisor()
returns trigger
language plpgsql
as $$
declare
  advisor_active boolean;
begin
  if new.is_active then
    select is_active into advisor_active from staff where id = new.staff_id;
    if advisor_active is null then
      raise exception 'that advisor does not exist';
    end if;
    if not advisor_active then
      raise exception 'a class cannot be assigned to a retired advisor';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists class_assignments_need_active_advisor on class_assignments;

create trigger class_assignments_need_active_advisor
  before insert or update on class_assignments
  for each row execute function class_needs_active_advisor();

-- ---------------------------------------------------------------------------
-- The report view keeps naming the advisor who actually handled the request
-- ---------------------------------------------------------------------------
-- No change needed: it joins od_requests.advisor_staff_id, which is pinned at
-- creation, so a retired advisor still appears on the ODs they approved. This
-- comment is here so nobody "fixes" it later by filtering on is_active.
