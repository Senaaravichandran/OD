-- Seeds the department: the HOD and the 13 class-advisor slots.
--
-- The roster is authoritative. Staff cannot sign themselves up, so these rows
-- are the complete set of people who may ever hold the ADVISOR or HOD role.
--
-- One wrinkle from the supplied data: Year 1 Section A and Year 1 Section B are
-- both listed against padmapriya@smvec.ac.in. An account is identified by its
-- email, so that is ONE staff member holding TWO classes - which is exactly
-- what class_assignments exists to express. Section B keeps the name the
-- department gave it (Periyasami) in advisor_label, so reports and the app show
-- the right name per class even though both sign in to the same account.

-- Per-class display name, for when a class is advised under another account.
alter table class_assignments
  add column if not exists advisor_label text;

comment on column class_assignments.advisor_label is
  'Name to show for this class when it differs from the staff account holder, e.g. Year 1 Section B is listed as Periyasami but signs in as padmapriya@smvec.ac.in.';

-- ---------------------------------------------------------------------------
-- Staff accounts
-- ---------------------------------------------------------------------------

with roster(email, name, is_hod) as (
  values
    ('hodit@smvec.ac.in',            'Dr. R. RAJU',    true),
    ('padmapriya@smvec.ac.in',       'Padmapriya',     false),
    ('maheshwaranit@smvec.ac.in',    'Maheshwaran',    false),
    ('vanaja.it@smvec.ac.in',        'Vanaja',         false),
    ('pradeesshma96@gmail.com',      'Pradheeshma',    false),
    ('valarmathie.it@smvec.ac.in',   'Valarmathi',     false),
    ('keerthanav.it@smvec.ac.in',    'Keerthana',      false),
    ('praveenkumarp.it@smvec.ac.in', 'Praveen Kumar',  false),
    ('ranjeeth.it@smvec.ac.in',      'Ranjeeth',       false),
    ('k.poornilashmi15@gmail.com',   'Poornambigai',   false),
    ('prabhu.it@smvec.ac.in',        'D Prabhu',       false),
    ('vijayakumarb.it@smvec.ac.in',  'Vijayakumar',    false),
    ('vijayprabhu.it@smvec.ac.in',   'Vijaya Prabhu',  false)
),
new_users as (
  insert into users (email, role, display_name)
  select email, case when is_hod then 'HOD'::user_role else 'ADVISOR'::user_role end, name
  from roster
  on conflict (email) do update
    set display_name = excluded.display_name,
        role         = excluded.role
  returning id, email
)
insert into staff (user_id, name, email, is_hod)
select u.id, r.name, r.email, r.is_hod
from roster r
join new_users u on u.email = r.email
on conflict (email) do update
  set name   = excluded.name,
      is_hod = excluded.is_hod;

-- ---------------------------------------------------------------------------
-- Class assignments
-- ---------------------------------------------------------------------------
-- Sections differ by year: Year 2 runs A-D, the others stop at C. Only these
-- 13 classes exist, so a student can never register into a class with no
-- advisor behind it.

with assignments(year, section, email, label) as (
  values
    (1, 'A', 'padmapriya@smvec.ac.in',       null),
    (1, 'B', 'padmapriya@smvec.ac.in',       'Periyasami'),
    (1, 'C', 'maheshwaranit@smvec.ac.in',    null),
    (2, 'A', 'vanaja.it@smvec.ac.in',        null),
    (2, 'B', 'pradeesshma96@gmail.com',      null),
    (2, 'C', 'valarmathie.it@smvec.ac.in',   null),
    (2, 'D', 'keerthanav.it@smvec.ac.in',    null),
    (3, 'A', 'praveenkumarp.it@smvec.ac.in', null),
    (3, 'B', 'ranjeeth.it@smvec.ac.in',      null),
    (3, 'C', 'k.poornilashmi15@gmail.com',   null),
    (4, 'A', 'prabhu.it@smvec.ac.in',        null),
    (4, 'B', 'vijayakumarb.it@smvec.ac.in',  null),
    (4, 'C', 'vijayprabhu.it@smvec.ac.in',   null)
)
insert into class_assignments (staff_id, year, section, batch, academic_year, advisor_label, is_active)
select
  s.id,
  a.year,
  a.section,
  -- A student in year N during the 2026-27 academic year entered in
  -- (2026 - N + 1), so year 3 is the 2024-2028 batch.
  ((2026 - a.year + 1)::text || '-' || (2026 - a.year + 5)::text),
  '2026-2027',
  a.label,
  true
from assignments a
join staff s on s.email = a.email
on conflict do nothing;
