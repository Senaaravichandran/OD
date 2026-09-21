-- Year 1 Section B gets its own advisor account.
--
-- The roster originally listed Periyasami against padmapriya@smvec.ac.in, so
-- 1-A and 1-B resolved to a single account and Section B's requests landed in
-- Padmapriya's dashboard. The department has since confirmed Periyasami's own
-- address, so Section B moves to it and the two classes are properly separate.
--
-- Section B's advisor_label is cleared at the same time: it existed only to
-- show the right name while the account was shared, and keeping it would now
-- mask the real account holder's name if it ever changed.

with new_user as (
  insert into users (email, role, display_name)
  values ('periyasami.it@smvec.ac.in', 'ADVISOR', 'Periyasami')
  on conflict (email) do update
    set display_name = excluded.display_name, role = excluded.role
  returning id
)
insert into staff (user_id, name, email, is_hod)
select id, 'Periyasami', 'periyasami.it@smvec.ac.in', false from new_user
on conflict (email) do update set name = excluded.name;

-- Point 1-B at the new account and drop the stand-in label.
update class_assignments
   set staff_id = (select id from staff where email = 'periyasami.it@smvec.ac.in'),
       advisor_label = null
 where year = 1 and section = 'B' and is_active;

-- Any request already filed under the shared account stays where it is: it was
-- genuinely received by that account, and moving it would rewrite history. Only
-- new requests from 1-B students route to Periyasami.
update students
   set class_assignment_id = (
         select id from class_assignments where year = 1 and section = 'B' and is_active
       )
 where year = 1 and section = 'B';
