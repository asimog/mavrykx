-- RLS and audit smoke test for 0001_core.sql
-- Run as a superuser after the schema. It seeds two matters, then switches to
-- the application role and proves that matter B is invisible to user A, and
-- that the proceeding-application tree stays inside one matter, shallow and
-- cycle-free (FD-15).
-- Expected: probes 1-2 print 1; probe 3 raises an RLS error; probes 4-5
-- print 0; probe 6 prints 1; probes 7-9 raise errors (cross-matter parent
-- not found, nesting deeper than 6, immutable parent); the audit check
-- prints 2 and t.

\set ON_ERROR_STOP off

-- --- seed as superuser (RLS bypassed) -------------------------------------
insert into app.firm (id, name) values
  ('00000000-0000-0000-0000-000000000001', 'Test Firm')
on conflict do nothing;

insert into app.user (id, email, display_name) values
  ('00000000-0000-0000-0000-000000000011', 'a@test.local', 'User A'),
  ('00000000-0000-0000-0000-000000000012', 'b@test.local', 'User B')
on conflict do nothing;

insert into app.membership (user_id, firm_id, role) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'lawyer'),
  ('00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000001', 'lawyer')
on conflict do nothing;

insert into app.contact (id, firm_id, kind, display_name) values
  ('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001', 'person', 'Client A'),
  ('00000000-0000-0000-0000-000000000022', '00000000-0000-0000-0000-000000000001', 'person', 'Client B')
on conflict do nothing;

insert into app.client (id, firm_id, contact_id) values
  ('00000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000021'),
  ('00000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000022')
on conflict do nothing;

insert into app.matter (id, firm_id, client_id, title, lead_user_id, status) values
  ('00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000031', 'Matter A', '00000000-0000-0000-0000-000000000011', 'active'),
  ('00000000-0000-0000-0000-000000000042', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000032', 'Matter B', '00000000-0000-0000-0000-000000000012', 'active')
on conflict do nothing;

insert into app.matter_member (matter_id, user_id, access, granted_by) values
  ('00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000011', 'lead', '00000000-0000-0000-0000-000000000011'),
  ('00000000-0000-0000-0000-000000000042', '00000000-0000-0000-0000-000000000012', 'lead', '00000000-0000-0000-0000-000000000012')
on conflict do nothing;

insert into app.document (id, matter_id, type_key, title, created_by) values
  ('00000000-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000041', 'pleading', 'A doc', '00000000-0000-0000-0000-000000000011'),
  ('00000000-0000-0000-0000-000000000052', '00000000-0000-0000-0000-000000000042', 'pleading', 'B doc', '00000000-0000-0000-0000-000000000012')
on conflict do nothing;

-- --- hand ownership to the migration role --------------------------------
-- In production the schema is created by maverick_owner. This test creates it
-- as postgres (for extensions), so ownership must be transferred before the
-- security-definer functions can read the membership tables.
alter schema app owner to maverick_owner;
alter schema audit owner to maverick_owner;
alter schema ref owner to maverick_owner;
alter schema ops owner to maverick_owner;

do $$
declare r record;
begin
  for r in select schemaname, tablename from pg_tables
           where schemaname in ('app','audit','ref','ops')
  loop
    execute format('alter table %I.%I owner to maverick_owner', r.schemaname, r.tablename);
  end loop;
  for r in select sequence_schema, sequence_name from information_schema.sequences
           where sequence_schema in ('app','audit')
  loop
    execute format('alter sequence %I.%I owner to maverick_owner', r.sequence_schema, r.sequence_name);
  end loop;
  for r in select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as args
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('app','audit')
  loop
    execute format('alter function %I.%I(%s) owner to maverick_owner', r.nspname, r.proname, r.args);
  end loop;
end $$;

grant usage on schema app, audit, ref, ops to maverick_owner;

-- --- act as the application role, user A ----------------------------------
set role maverick_app;
select set_config('app.user_id', '00000000-0000-0000-0000-000000000011', false);

\echo 'probe 1: matters visible to user A (expect 1)'
select count(*) from app.matter;

\echo 'probe 2: documents visible to user A (expect 1)'
select count(*) from app.document;

\echo 'probe 3: cross-matter insert by user A (expect RLS error)'
insert into app.document (matter_id, type_key, title, created_by)
values ('00000000-0000-0000-0000-000000000042', 'pleading', 'intrusion', '00000000-0000-0000-0000-000000000011');

\echo 'probe 4: user B matters visible to user A (expect 0)'
select count(*) from app.matter where id = '00000000-0000-0000-0000-000000000042';

-- --- ethical wall ---------------------------------------------------------
reset role;
insert into app.ethical_wall (matter_id, user_id, reason, created_by)
values ('00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000011', 'test wall', '00000000-0000-0000-0000-000000000012')
on conflict do nothing;

set role maverick_app;
select set_config('app.user_id', '00000000-0000-0000-0000-000000000011', false);

\echo 'probe 5: walled user sees no matter (expect 0)'
select count(*) from app.matter;

-- --- application tree (FD-15) ----------------------------------------------
reset role;

-- lift the test wall so user A can act on matter A again (and prove the
-- revoked wall no longer denies)
update app.ethical_wall set revoked_at = now()
  where matter_id = '00000000-0000-0000-0000-000000000041'
    and user_id = '00000000-0000-0000-0000-000000000011';

insert into app.forum (id, name, level) values
  ('00000000-0000-0000-0000-000000000061', 'Test High Court', 'high_court')
on conflict do nothing;

insert into app.proceeding (id, matter_id, forum_id, case_number, status) values
  ('00000000-0000-0000-0000-000000000071', '00000000-0000-0000-0000-000000000041',
   '00000000-0000-0000-0000-000000000061', 'BAIL 1/2026', 'pending'),
  ('00000000-0000-0000-0000-000000000072', '00000000-0000-0000-0000-000000000042',
   '00000000-0000-0000-0000-000000000061', 'CS 2/2026', 'pending')
on conflict do nothing;

insert into app.proceeding_application (id, matter_id, proceeding_id, kind, title) values
  ('00000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-000000000041',
   '00000000-0000-0000-0000-000000000071', 'bail', 'Bail Application'),
  ('00000000-0000-0000-0000-000000000082', '00000000-0000-0000-0000-000000000042',
   '00000000-0000-0000-0000-000000000072', 'stay', 'Stay Application')
on conflict do nothing;

set role maverick_app;
select set_config('app.user_id', '00000000-0000-0000-0000-000000000011', false);

\echo 'probe 6: nested application under own-matter parent (expect 1)'
insert into app.proceeding_application
  (matter_id, parent_application_id, kind, title) values
  ('00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000081',
   'other', 'Clarification of bail conditions');
select count(*) from app.proceeding_application
  where parent_application_id = '00000000-0000-0000-0000-000000000081';

\echo 'probe 7: nested application under another matter application (expect error 23503)'
insert into app.proceeding_application
  (matter_id, parent_application_id, kind, title) values
  ('00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000082',
   'other', 'Intrusion child');

reset role;

\echo 'probe 8: nesting deeper than 6 (expect error 23514)'
do $$
declare
  v_parent uuid := '00000000-0000-0000-0000-000000000081';
  v_id uuid;
begin
  for i in 1..6 loop
    v_id := gen_random_uuid();
    insert into app.proceeding_application (id, matter_id, parent_application_id, kind, title)
    values (v_id, '00000000-0000-0000-0000-000000000041', v_parent, 'other', 'L' || i);
    v_parent := v_id;
  end loop;
end $$;
insert into app.proceeding_application (id, matter_id, parent_application_id, kind, title)
values ('00000000-0000-0000-0000-000000000097', '00000000-0000-0000-0000-000000000041',
        (select id from app.proceeding_application
          where depth = 6 and matter_id = '00000000-0000-0000-0000-000000000041'
          order by created_at desc limit 1),
        'other', 'One level too deep');

\echo 'probe 9: re-parenting an application (expect error 55000)'
update app.proceeding_application
  set parent_application_id = '00000000-0000-0000-0000-000000000082'
  where id = '00000000-0000-0000-0000-000000000081';

-- --- audit chain ----------------------------------------------------------
reset role;
select audit.append('user', '00000000-0000-0000-0000-000000000011', 'test.one', 'matter',
                    '00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000041', 'req-1', '{"n":1}');
select audit.append('user', '00000000-0000-0000-0000-000000000011', 'test.two', 'matter',
                    '00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000041', 'req-2', '{"n":2}');

\echo 'audit rows and chain link (expect 2 and t)'
select count(*), bool_and(hash is not null) from audit.audit_event;
select (select hash from audit.audit_event order by seq desc offset 1 limit 1) =
       (select prev_hash from audit.audit_event order by seq desc limit 1) as last_links_to_prev;
