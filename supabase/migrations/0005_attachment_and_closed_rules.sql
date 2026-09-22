-- Two gaps the rules test found in the workflow triggers.
--
-- 1. od_results may only be written once the OD is sanctioned, and the API
--    applies the same rule to attachments - but the database did not, so a
--    code path that skipped the check could have filed a certificate against
--    a request nobody had approved. The trigger closes that.
--
-- 2. A request that has already closed reported the wrong reason. Rejecting
--    an approved OD matched the "HOD decision requires advisor approval
--    first" branch, which is true but misleading: the real answer is that the
--    decision has already been made. Checking closure first says so.

-- ---------------------------------------------------------------------------
-- Attachments follow the same rule as results
-- ---------------------------------------------------------------------------

create or replace function enforce_file_requires_approval()
returns trigger
language plpgsql
as $$
declare
  req_status od_status;
begin
  select status into req_status from od_requests where id = new.od_request_id;
  if req_status is null then
    raise exception 'the OD request this file belongs to does not exist';
  end if;
  if req_status <> 'APPROVED' then
    raise exception 'a file can only be attached to an approved OD (status is %)', req_status;
  end if;
  return new;
end;
$$;

comment on function enforce_file_requires_approval is
  'Certificates and prize photos are evidence of a sanctioned OD, so they cannot be attached before the HOD has approved it. The API checks this too; this is the guarantee.';

drop trigger if exists result_files_requires_approval on result_files;

create trigger result_files_requires_approval before insert or update on result_files
  for each row execute function enforce_file_requires_approval();

-- ---------------------------------------------------------------------------
-- Say the right thing about a closed request
-- ---------------------------------------------------------------------------

create or replace function enforce_od_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  -- First, because it is the most specific answer: once a decision has been
  -- made the request is finished, whichever way the caller tries to move it.
  if old.status in ('APPROVED', 'REJECTED_HOD', 'REJECTED_ADVISOR') then
    raise exception 'request is already closed (%), it cannot change again', old.status;
  end if;

  if old.status <> 'PENDING_ADVISOR'
     and new.status in ('APPROVED_BY_ADVISOR', 'REJECTED_ADVISOR') then
    raise exception 'advisor decision is only valid while the request is pending advisor review (was %)', old.status;
  end if;

  if new.status in ('APPROVED', 'REJECTED_HOD')
     and old.status <> 'APPROVED_BY_ADVISOR' then
    raise exception 'HOD decision requires advisor approval first (was %)', old.status;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- The last permissive policy
-- ---------------------------------------------------------------------------
-- class_assignments allowed the anon and authenticated keys to read the class
-- grid. Nothing needs it: the API talks to Postgres as the service role, and
-- the public class list is served by the CLASSES action, which decides for
-- itself what to publish. Dropping it returns the database to "no permissive
-- policies at all", so a leaked anon key reads nothing anywhere.

drop policy if exists class_assignments_public_read on class_assignments;
