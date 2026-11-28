-- RLS and audit smoke test for 0001_core.sql
-- Run as a superuser after the schema. It seeds two Matters and one firm admin,
-- then switches to the application role and proves that:
--   * Matter B is invisible to user A;
--   * the firm admin sees both Matters and a restricted document;
--   * a restricted document and its version/text rows are invisible to a
--     Matter member without a resource grant;
--   * the proceeding-application tree stays inside one Matter, shallow and
--     cycle-free (FD-15);
--   * the audit chain links and carries the new actor/trigger/approval fields.
-- Expected: probes 1-2 print 1; probe 3 raises an RLS error; probes 4-7 print 0;
-- probe 8 prints 2; probe 9 prints 1; probe 10 prints 1; probes 11-13 and 15
-- raise errors; probe 14 prints 1; the audit check prints 3 and t.

\set ON_ERROR_STOP off

-- --- seed as superuser (RLS bypassed) -------------------------------------
insert into app.firm (id, name) values
  ('00000000-0000-0000-0000-000000000001', 'Test Firm')
on conflict do nothing;

insert into app.user (id, email, display_name) values
  ('00000000-0000-0000-0000-000000000011', 'a@test.local', 'User A'),
  ('00000000-0000-0000-0000-000000000012', 'b@test.local', 'User B'),
  ('00000000-0000-0000-0000-000000000013', 'admin@test.local', 'Firm Admin'),
  ('00000000-0000-0000-0000-000000000014', 'c@test.local', 'User C'),
  ('00000000-0000-0000-0000-000000000015', 'd@test.local', 'User D')
on conflict do nothing;

insert into app.membership (user_id, firm_id, role) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'lawyer'),
  ('00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000001', 'lawyer'),
  ('00000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000001', 'admin'),
  ('00000000-0000-0000-0000-000000000014', '00000000-0000-0000-0000-000000000001', 'lawyer'),
  ('00000000-0000-0000-0000-000000000015', '00000000-0000-0000-0000-000000000001', 'lawyer')
on conflict do nothing;

insert into app.contact (id, firm_id, kind, display_name) values
  ('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001', 'person', 'Client A'),
  ('00000000-0000-0000-0000-000000000022', '00000000-0000-0000-0000-000000000001', 'person', 'Client B')
on conflict do nothing;

insert into app.client (id, firm_id, contact_id) values
  ('00000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000021'),
  ('00000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000022')
on conflict do nothing;

insert into app.matter (id, firm_id, client_id, title, responsible_user_id, status) values
  ('00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000031', 'Matter A', '00000000-0000-0000-0000-000000000011', 'active'),
  ('00000000-0000-0000-0000-000000000042', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000032', 'Matter B', '00000000-0000-0000-0000-000000000012', 'active')
on conflict do nothing;

insert into app.matter_member (matter_id, user_id, access, granted_by) values
  ('00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000011', 'edit', '00000000-0000-0000-0000-000000000011'),
  ('00000000-0000-0000-0000-000000000042', '00000000-0000-0000-0000-000000000012', 'edit', '00000000-0000-0000-0000-000000000012'),
  ('00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000015', 'edit', '00000000-0000-0000-0000-000000000013')
on conflict do nothing;

insert into app.delegation (id, firm_id, delegator_user_id, delegate_user_id, scope) values
  ('00000000-0000-0000-0000-0000000000a1',
   '00000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000013',
   '00000000-0000-0000-0000-000000000015',
   'access')
on conflict do nothing;

insert into app.document (id, matter_id, type_key, title, created_by, confidentiality) values
  ('00000000-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000041', 'pleading', 'A doc', '00000000-0000-0000-0000-000000000011', 'matter'),
  ('00000000-0000-0000-0000-000000000052', '00000000-0000-0000-0000-000000000042', 'pleading', 'B doc', '00000000-0000-0000-0000-000000000012', 'matter'),
  ('00000000-0000-0000-0000-000000000053', '00000000-0000-0000-0000-000000000041', 'pleading', 'A restricted doc', '00000000-0000-0000-0000-000000000011', 'restricted')
on conflict do nothing;

insert into app.blob (sha256, size, mime, storage_key) values
  (repeat('a', 64), 1, 'application/pdf', 'test/restricted')
on conflict do nothing;

insert into app.document_version
  (id, matter_id, document_id, version_no, blob_sha256, source, created_by)
values
  ('00000000-0000-0000-0000-000000000061',
   '00000000-0000-0000-0000-000000000041',
   '00000000-0000-0000-0000-000000000053',
   1, repeat('a', 64), 'upload', '00000000-0000-0000-0000-000000000011')
on conflict do nothing;

insert into app.document_text (document_version_id, matter_id, text, text_hash) values
  ('00000000-0000-0000-0000-000000000061',
   '00000000-0000-0000-0000-000000000041',
   'restricted text', 'test-hash')
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

\echo 'probe 2: documents visible to user A (expect 1; the restricted document is excluded)'
select count(*) from app.document;

\echo 'probe 3: cross-matter insert by user A (expect RLS error)'
insert into app.document (matter_id, type_key, title, created_by)
values ('00000000-0000-0000-0000-000000000042', 'pleading', 'intrusion', '00000000-0000-0000-0000-000000000011');

\echo 'probe 4: user B matters visible to user A (expect 0)'
select count(*) from app.matter where id = '00000000-0000-0000-0000-000000000042';

\echo 'probe 5: restricted document rows visible to user A (expect 0)'
select count(*) from app.document where id = '00000000-0000-0000-0000-000000000053';

\echo 'probe 6: restricted versions visible to user A (expect 0)'
select count(*) from app.document_version where document_id = '00000000-0000-0000-0000-000000000053';

\echo 'probe 7: restricted text visible to user A (expect 0)'
select count(*) from app.document_text where document_version_id = '00000000-0000-0000-0000-000000000061';

-- --- firm admin sees every Matter and restricted document -----------------
select set_config('app.user_id', '00000000-0000-0000-0000-000000000013', false);

\echo 'probe 8: matters visible to the firm admin (expect 2)'
select count(*) from app.matter;

\echo 'probe 9: restricted versions visible to the firm admin (expect 1)'
select count(*) from app.document_version where document_id = '00000000-0000-0000-0000-000000000053';

-- --- application tree (FD-15) ----------------------------------------------
reset role;

insert into app.forum (id, name, level) values
  ('00000000-0000-0000-0000-000000000071', 'Test High Court', 'high_court')
on conflict do nothing;

insert into app.proceeding (id, matter_id, forum_id, case_number, status) values
  ('00000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-000000000041',
   '00000000-0000-0000-0000-000000000071', 'BAIL 1/2026', 'pending'),
  ('00000000-0000-0000-0000-000000000082', '00000000-0000-0000-0000-000000000042',
   '00000000-0000-0000-0000-000000000071', 'CS 2/2026', 'pending')
on conflict do nothing;

insert into app.proceeding_application (id, matter_id, proceeding_id, kind, title) values
  ('00000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000000041',
   '00000000-0000-0000-0000-000000000081', 'bail', 'Bail Application'),
  ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000042',
   '00000000-0000-0000-0000-000000000082', 'stay', 'Stay Application')
on conflict do nothing;

set role maverick_app;
select set_config('app.user_id', '00000000-0000-0000-0000-000000000011', false);

\echo 'probe 10: nested application under own-matter parent (expect 1)'
insert into app.proceeding_application
  (matter_id, parent_application_id, kind, title) values
  ('00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000091',
   'other', 'Clarification of bail conditions');
select count(*) from app.proceeding_application
  where parent_application_id = '00000000-0000-0000-0000-000000000091';

\echo 'probe 11: nested application under another matter application (expect error 23503)'
insert into app.proceeding_application
  (matter_id, parent_application_id, kind, title) values
  ('00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000092',
   'other', 'Intrusion child');

reset role;

\echo 'probe 12: nesting deeper than 6 (expect error 23514)'
do $$
declare
  v_parent uuid := '00000000-0000-0000-0000-000000000091';
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
values ('00000000-0000-0000-0000-000000000099', '00000000-0000-0000-0000-000000000041',
        (select id from app.proceeding_application
          where depth = 6 and matter_id = '00000000-0000-0000-0000-000000000041'
          order by created_at desc limit 1),
        'other', 'One level too deep');

\echo 'probe 13: re-parenting an application (expect error 55000)'
update app.proceeding_application
  set parent_application_id = '00000000-0000-0000-0000-000000000092'
  where id = '00000000-0000-0000-0000-000000000091';

-- --- delegated access and view-vs-edit --------------------------------
set role maverick_app;
select set_config('app.user_id', '00000000-0000-0000-0000-000000000015', false);

\echo 'probe 14: delegated access adds user C as view (expect 1)'
with ins as (
  insert into app.matter_member (matter_id, user_id, access, granted_by)
  values ('00000000-0000-0000-0000-000000000041',
          '00000000-0000-0000-0000-000000000014',
          'view',
          '00000000-0000-0000-0000-000000000015')
  returning 1
)
select count(*) from ins;

select set_config('app.user_id', '00000000-0000-0000-0000-000000000014', false);

\echo 'probe 15: view member insert into note (expect RLS error)'
insert into app.note (matter_id, author_id, body)
values ('00000000-0000-0000-0000-000000000041',
        '00000000-0000-0000-0000-000000000014',
        'view intrusion');

-- --- audit chain ----------------------------------------------------------
reset role;
select audit.append('user', '00000000-0000-0000-0000-000000000011', 'test.one', 'matter',
                    '00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000041', 'req-1', '{"n":1}');
select audit.append('user', '00000000-0000-0000-0000-000000000011', 'test.two', 'matter',
                    '00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000041', 'req-2', '{"n":2}');
select audit.append('service', null, 'test.three', 'matter',
                    '00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000041', 'req-3', '{"n":3}',
                    'google-drive', 'delegation', null,
                    '00000000-0000-0000-0000-000000000011', 'approved',
                    '00000000-0000-0000-0000-000000000013');

\echo 'audit rows and chain link (expect 3 and t)'
select count(*), bool_and(hash is not null) from audit.audit_event;
select (select hash from audit.audit_event order by seq desc offset 1 limit 1) =
       (select prev_hash from audit.audit_event order by seq desc limit 1) as last_links_to_prev;

\echo 'audit actor fields (expect service, google-drive, delegation, t, approved)'
select actor_type, actor_ref, trigger_type,
       initiating_user_id is not null as has_initiator, approval_status
from audit.audit_event order by seq desc limit 1;
