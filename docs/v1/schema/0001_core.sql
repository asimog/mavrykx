-- MavrykX core schema - the single baseline.
-- PostgreSQL 17+. Run as the migration role (maverick_owner).
-- Appendix to the domain model (docs/v1/02-domain-model.md). It is intentionally
-- not every entity: issue/argument and time/billing are designed in the model
-- and built with their owning work. The domain model is the source; if they
-- conflict, fix this file.
--
-- Conventions:
--   * UUID keys, timestamptz, text + CHECK for stable sets.
--   * Every Matter-bound legal table carries matter_id and has RLS.
--   * Immutable tables reject UPDATE and DELETE.
--   * Derived data (text, anchors, chunks) is separate and rebuildable.

create extension if not exists pgcrypto;
create extension if not exists citext;
create extension if not exists pg_trgm;
create extension if not exists vector;

create schema if not exists app;
create schema if not exists audit;
create schema if not exists ref;
create schema if not exists ops;

-- ---------------------------------------------------------------------------
-- Roles (cluster-level; idempotent)
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'maverick_owner') then
    create role maverick_owner nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'maverick_app') then
    create role maverick_app nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'maverick_readonly') then
    create role maverick_readonly nologin;
  end if;
end $$;

grant usage on schema app, audit, ref, ops to maverick_app, maverick_readonly;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function app.current_user() returns uuid
language sql stable as $$
  select nullif(current_setting('app.user_id', true), '')::uuid
$$;

-- Access functions are defined after the tables they read (see "Access
-- functions" below). SQL-language functions validate their bodies at creation,
-- so defining them before app.membership exists fails the migration.

create or replace function app.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create or replace function app.reject_mutation() returns trigger
language plpgsql as $$
begin
  raise exception 'immutable table: %', tg_table_name using errcode = '55000';
end $$;

-- ---------------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------------
create table ref.document_type (
  key            text primary key,
  label          text not null,
  category       text not null check (category in
                   ('court_facing','application','affidavit','evidence','advice',
                    'transactional','correspondence','internal','order','other')),
  description    text,
  is_active      boolean not null default true,
  sort_order     int not null default 100,
  created_at     timestamptz not null default now()
);

insert into ref.document_type (key, label, category) values
  ('pleading',      'Pleading',            'court_facing'),
  ('petition',      'Petition',            'court_facing'),
  ('written_statement','Written Statement','court_facing'),
  ('application',   'Application',         'application'),
  ('affidavit',     'Affidavit',           'affidavit'),
  ('evidence',      'Evidence',            'evidence'),
  ('memo',          'Memorandum',          'advice'),
  ('opinion',       'Opinion',             'advice'),
  ('contract',      'Contract',            'transactional'),
  ('notice',        'Notice',              'correspondence'),
  ('correspondence','Correspondence',      'correspondence'),
  ('note',          'Internal Note',       'internal'),
  ('order',         'Order / Judgment',    'order'),
  ('other',         'Other',               'other')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Firm, users, access
-- ---------------------------------------------------------------------------
create table app.firm (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  jurisdiction   text,
  default_tz     text not null default 'Asia/Kolkata',
  retention_days int not null default 2555 check (retention_days between 30 and 36500),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint firm_singleton check (id is not null)
);
create unique index firm_one_row on app.firm ((true));

create table app.user (
  id             uuid primary key default gen_random_uuid(),
  email          citext not null unique,
  display_name   text not null,
  password_hash  text,
  totp_secret    text,
  status         text not null default 'active' check (status in ('invited','active','suspended','disabled')),
  last_login_at  timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table app.membership (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references app.user(id) on delete cascade,
  firm_id        uuid not null references app.firm(id) on delete cascade,
  role           text not null check (role in ('admin','lawyer','staff','intern')),
  title          text,
  disabled_at    timestamptz,
  created_at     timestamptz not null default now(),
  unique (user_id, firm_id)
);

create table app.contact (
  id             uuid primary key default gen_random_uuid(),
  firm_id        uuid not null references app.firm(id) on delete cascade,
  kind           text not null check (kind in ('person','organisation')),
  display_name   text not null,
  legal_name     text,
  email          citext,
  phone          text,
  address        text,
  registration   text,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index contact_name_trgm on app.contact using gin (display_name gin_trgm_ops);
create index contact_email on app.contact (email);

create table app.client (
  id             uuid primary key default gen_random_uuid(),
  firm_id        uuid not null references app.firm(id) on delete cascade,
  contact_id     uuid not null unique references app.contact(id),
  status         text not null default 'active' check (status in ('prospect','active','inactive','closed')),
  kyc_status     text not null default 'pending' check (kyc_status in ('pending','verified','failed','waived')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table app.matter (
  id             uuid primary key default gen_random_uuid(),
  firm_id        uuid not null references app.firm(id) on delete cascade,
  client_id      uuid references app.client(id),
  code           text,
  title          text not null,
  description    text,
  practice_area  text,
  status         text not null default 'intake' check (status in
                   ('intake','gate_pending','active','on_hold','closed','archived')),
  confidentiality text not null default 'normal' check (confidentiality in ('normal','high','restricted')),
  responsible_user_id uuid not null references app.user(id),
  opened_at      timestamptz,
  closed_at      timestamptz,
  retention_until date,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (firm_id, code)
);
create index matter_client on app.matter (client_id);
create index matter_status on app.matter (firm_id, status);

create table app.matter_member (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  user_id        uuid not null references app.user(id) on delete cascade,
  access         text not null check (access in ('edit','view')),
  granted_by     uuid not null references app.user(id),
  granted_at     timestamptz not null default now(),
  revoked_at     timestamptz
);
create unique index matter_member_user on app.matter_member (matter_id, user_id)
  where revoked_at is null;

create table app.matter_party (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  contact_id     uuid not null references app.contact(id),
  role           text not null check (role in
                   ('client','opposing','co_party','witness','expert','counsel','authority','other')),
  side           text check (side in ('our','their','neutral')),
  capacity       text,
  created_at     timestamptz not null default now(),
  unique (matter_id, contact_id, role)
);

create table app.matter_relation (
  id             uuid primary key default gen_random_uuid(),
  from_matter_id uuid not null references app.matter(id) on delete cascade,
  to_matter_id   uuid not null references app.matter(id) on delete cascade,
  relation       text not null check (relation in ('appeal_from','related','consolidated','cross_reference')),
  note           text,
  created_at     timestamptz not null default now(),
  check (from_matter_id <> to_matter_id),
  unique (from_matter_id, to_matter_id, relation)
);

create table app.reuse_grant (
  id             uuid primary key default gen_random_uuid(),
  source_matter_id uuid not null references app.matter(id) on delete cascade,
  target_matter_id uuid not null references app.matter(id) on delete cascade,
  purpose        text not null,
  fields         text[] not null default '{}',
  approved_by    uuid not null references app.user(id),
  approved_at    timestamptz not null default now(),
  expires_at     timestamptz,
  created_at     timestamptz not null default now(),
  check (source_matter_id <> target_matter_id)
);
create index reuse_grant_target on app.reuse_grant (target_matter_id, expires_at);

-- ---------------------------------------------------------------------------
-- Forums, proceedings, hearings, orders
-- ---------------------------------------------------------------------------
create table app.forum (
  id             uuid primary key default gen_random_uuid(),
  parent_id      uuid references app.forum(id),
  name           text not null,
  short_name     text,
  level          text not null check (level in
                   ('country','state','high_court','district_court','tribunal','authority','arbitral_seat','other')),
  jurisdiction   text,
  code           text,
  aliases        text[] not null default '{}',
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  unique (parent_id, name)
);

create table app.proceeding (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  forum_id       uuid not null references app.forum(id),
  case_number    text,
  case_type_key  text,
  stage_key      text,
  our_side       text check (our_side in ('petitioner','respondent','plaintiff','defendant','appellant','other')),
  status         text not null default 'prospective' check (status in
                   ('prospective','filed','pending','reserved','disposed','appealed','withdrawn')),
  filed_on       date,
  disposed_on    date,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index proceeding_case on app.proceeding (matter_id, forum_id, case_number)
  where case_number is not null;
create index proceeding_matter on app.proceeding (matter_id, status);

create table app.hearing (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  proceeding_id  uuid not null references app.proceeding(id) on delete cascade,
  scheduled_at   timestamptz not null,
  purpose        text,
  status         text not null default 'scheduled' check (status in
                   ('scheduled','held','adjourned','cancelled','not_reached')),
  outcome        text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index hearing_calendar on app.hearing (matter_id, scheduled_at);
create index hearing_proceeding on app.hearing (proceeding_id, scheduled_at);

create table app."order" (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  proceeding_id  uuid not null references app.proceeding(id) on delete cascade,
  hearing_id     uuid references app.hearing(id) on delete set null,
  decided_on     date not null,
  kind           text not null default 'order' check (kind in ('order','judgment','decree','award','direction')),
  operative_text text,
  directions     jsonb not null default '[]'::jsonb,
  next_date      date,
  document_id    uuid,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index order_proceeding on app."order" (proceeding_id, decided_on desc);

-- Applications: bail, stay, injunction, restoration, exemption, recall, and
-- their children (clarification, modification, recall of an order passed on
-- an application). First-class lifecycle (FD-14); nested as a tree (FD-15):
-- a row is a direct child of a matter (pre-forum, before the forum assigns
-- a case number), of a proceeding, or of another application. Context is
-- inherited down the chain unless a row blocks it (inherit_context);
-- archived once resolved, never deleted. Adjacency list + recursive CTE;
-- guards keep each tree inside one matter, shallow, and cycle-free.
create table app.proceeding_application (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  parent_application_id uuid references app.proceeding_application(id) on delete cascade,
  proceeding_id  uuid references app.proceeding(id) on delete cascade,
  depth          smallint not null default 0 check (depth between 0 and 6),
  inherit_context boolean not null default true,
  context_note   text,
  kind           text not null default 'interim' check (kind in
                   ('bail','stay','injunction','restoration','exemption','recall','interim','other')),
  title          text not null,
  status         text not null default 'contemplated' check (status in
                   ('contemplated','filed','decided','withdrawn','archived')),
  outcome        text check (outcome in ('allowed','dismissed','partly_allowed','withdrawn','other')),
  filed_on       date,
  decided_on     date,
  order_id       uuid references app."order"(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint application_no_self_parent check (parent_application_id is distinct from id)
);
create index proceeding_application_active on app.proceeding_application (matter_id, status)
  where status not in ('archived');
create index proceeding_application_proceeding on app.proceeding_application (proceeding_id);
create index proceeding_application_parent on app.proceeding_application (parent_application_id);

-- ---------------------------------------------------------------------------
-- Work: tasks, deadlines, appointments, notes, decisions
-- ---------------------------------------------------------------------------
create table app.task (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  proceeding_id  uuid references app.proceeding(id) on delete set null,
  title          text not null,
  detail         text,
  work_kind      text not null default 'general' check (work_kind in
                   ('draft','research','review','filing','hearing_prep','client','admin','general')),
  status         text not null default 'open' check (status in
                   ('open','in_progress','blocked','done','cancelled')),
  priority       smallint not null default 3 check (priority between 1 and 5),
  assignee_id    uuid references app.user(id),
  due_at         timestamptz,
  source         text not null default 'human' check (source in ('human','agent','order','playbook')),
  completed_at   timestamptz,
  created_by     uuid not null references app.user(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index task_today on app.task (matter_id, status, due_at);
create index task_assignee on app.task (assignee_id, status, due_at);

create table app.deadline (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  proceeding_id  uuid references app.proceeding(id) on delete set null,
  kind           text not null check (kind in ('limitation','statutory','order','internal','hearing')),
  title          text not null,
  basis_type     text not null check (basis_type in ('statute','rule','order','manual')),
  basis_ref      text,
  computed_from  date,
  due_at         date not null,
  override_at    date,
  status         text not null default 'proposed' check (status in
                   ('proposed','confirmed','met','missed','waived')),
  verified_by    uuid references app.user(id),
  verified_at    timestamptz,
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint deadline_basis check (basis_type <> 'manual' or note is not null)
);
create index deadline_calendar on app.deadline (matter_id, due_at);
create index deadline_open on app.deadline (status, due_at) where status in ('proposed','confirmed');

create table app.appointment (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  title          text not null,
  starts_at      timestamptz not null,
  ends_at        timestamptz not null,
  location       text,
  attendees      jsonb not null default '[]'::jsonb,
  created_by     uuid not null references app.user(id),
  created_at     timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table app.note (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  author_id      uuid not null references app.user(id),
  body           text not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table app.decision (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  subject_type   text not null,
  subject_id     uuid,
  decision_type  text not null,
  options        jsonb not null default '[]'::jsonb,
  chosen         jsonb not null,
  rationale      text,
  decided_by     uuid not null references app.user(id),
  decided_by_contact_id uuid references app.contact(id),
  decided_at     timestamptz not null default now(),
  subject_hash   text,
  created_at     timestamptz not null default now()
);
create index decision_matter on app.decision (matter_id, decided_at desc);

create table app.approval (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  subject_type   text not null check (subject_type in
                   ('document_version','filing','access_grant','rule_publication','deletion','external_send')),
  subject_id     uuid not null,
  subject_hash   text not null,
  action         text not null,
  requested_by   uuid references app.user(id),
  requested_run_id uuid,
  required_role  text,
  status         text not null default 'pending' check (status in
                   ('pending','approved','rejected','expired','stale')),
  decided_by     uuid references app.user(id),
  decided_at     timestamptz,
  expires_at     timestamptz,
  note           text,
  created_at     timestamptz not null default now()
);
create index approval_pending on app.approval (matter_id, status) where status = 'pending';
create unique index approval_one_pending on app.approval (subject_type, subject_id, action)
  where status = 'pending';

-- ---------------------------------------------------------------------------
-- Storage and documents
-- ---------------------------------------------------------------------------
create table app.blob (
  sha256         text primary key check (sha256 ~ '^[0-9a-f]{64}$'),
  size           bigint not null check (size >= 0),
  mime           text not null,
  storage_key    text not null,
  verified_at    timestamptz,
  created_at     timestamptz not null default now()
);

-- Matter folders: the arrangement layer (FD-13). Metadata only; the blob store
-- keeps the bytes. Default folders are seeded from document_type.
create table app.folder (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  parent_id      uuid references app.folder(id) on delete cascade,
  name           text not null,
  ordinal        int not null default 0,
  created_at     timestamptz not null default now()
);
create unique index folder_unique on app.folder
  (matter_id, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), name);
create index folder_matter on app.folder (matter_id);

create table app.document (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  folder_id      uuid references app.folder(id) on delete set null,
  type_key       text not null references ref.document_type(key),
  title          text not null,
  status         text not null default 'draft' check (status in
                   ('draft','in_review','approved','filed','superseded','archived')),
  confidentiality text not null default 'matter' check (confidentiality in ('matter','restricted')),
  current_version_id uuid,
  created_by     uuid not null references app.user(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index document_matter on app.document (matter_id, status);
create index document_folder on app.document (folder_id);

create table app.document_version (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  document_id    uuid not null references app.document(id) on delete cascade,
  version_no     int not null check (version_no > 0),
  blob_sha256    text not null references app.blob(sha256),
  base_version_id uuid references app.document_version(id),
  source         text not null check (source in
                   ('upload','agent_generated','editor_save','import','template','export')),
  idempotency_key text,
  created_by     uuid references app.user(id),
  created_run_id uuid,
  origin_task_id uuid references app.task(id),
  origin_decision_id uuid references app.decision(id),
  page_count     int,
  created_at     timestamptz not null default now(),
  unique (document_id, version_no),
  check (source <> 'agent_generated' or origin_task_id is not null or origin_decision_id is not null)
);
create index document_version_current on app.document_version (document_id, version_no desc);
create index document_version_blob on app.document_version (blob_sha256);
create unique index document_version_idempotency
  on app.document_version (document_id, idempotency_key)
  where idempotency_key is not null;

-- Derived text is rebuildable; text_hash pins the exact text an extraction was
-- built from (RD-61). A re-OCR changes the hash and marks dependent extractions
-- stale into the review queue.
create table app.document_text (
  document_version_id uuid primary key references app.document_version(id) on delete cascade,
  matter_id      uuid not null references app.matter(id) on delete cascade,
  text           text not null,
  text_hash      text not null,
  pages          jsonb not null default '[]'::jsonb,
  ocr_confidence real,
  extracted_at   timestamptz not null default now(),
  search_doc     tsvector generated always as (to_tsvector('english', coalesce(text,''))) stored
);
create index document_text_search on app.document_text using gin (search_doc);

create table app.document_anchor (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  document_version_id uuid not null references app.document_version(id) on delete cascade,
  anchor_key     text not null,
  kind           text not null check (kind in ('heading','paragraph','table_row','list_item','footnote')),
  ordinal        int not null,
  text_hash      text not null,
  text_preview   text,
  unique (document_version_id, anchor_key)
);

create table app.document_relation (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  from_document_id uuid not null references app.document(id) on delete cascade,
  to_document_id uuid not null references app.document(id) on delete cascade,
  relation       text not null check (relation in
                   ('exhibit','annexure','attachment','supersedes','translation_of','filed_with','derived_from')),
  note           text,
  created_at     timestamptz not null default now(),
  check (from_document_id <> to_document_id),
  unique (from_document_id, to_document_id, relation)
);

create table app.annotation (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  document_version_id uuid not null references app.document_version(id) on delete cascade,
  anchor_key     text,
  author_id      uuid not null references app.user(id),
  body           text not null,
  status         text not null default 'open' check (status in ('open','resolved','wont_fix')),
  resolved_at    timestamptz,
  created_at     timestamptz not null default now()
);

create table app.template (
  id             uuid primary key default gen_random_uuid(),
  type_key       text not null references ref.document_type(key),
  name           text not null,
  version        int not null default 1,
  blob_sha256    text not null references app.blob(sha256),
  variables_schema jsonb not null default '{}'::jsonb,
  scope          jsonb not null default '{}'::jsonb,
  status         text not null default 'draft' check (status in ('draft','published','retired')),
  verified_by    uuid references app.user(id),
  verified_at    timestamptz,
  created_at     timestamptz not null default now(),
  unique (type_key, name, version)
);

create table app.document_chunk (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  document_version_id uuid not null references app.document_version(id) on delete cascade,
  ordinal        int not null,
  text           text not null,
  token_count    int not null,
  embedding      vector(1024),
  embedding_model text,
  created_at     timestamptz not null default now(),
  unique (document_version_id, ordinal)
);
create index document_chunk_embedding on app.document_chunk
  using hnsw (embedding vector_cosine_ops);

alter table app.document
  add constraint document_current_version_fk
  foreign key (current_version_id) references app.document_version(id);

-- ---------------------------------------------------------------------------
-- Filings
-- ---------------------------------------------------------------------------
create table app.filing (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  proceeding_id  uuid not null references app.proceeding(id) on delete cascade,
  forum_id       uuid not null references app.forum(id),
  filing_type    text not null,
  status         text not null default 'prepared' check (status in
                   ('prepared','submitted','accepted','defects','re_filed','closed')),
  submitted_at   timestamptz,
  acknowledgment_no text,
  fees           jsonb not null default '{}'::jsonb,
  response       jsonb not null default '{}'::jsonb,
  authorised_by_task_id uuid references app.task(id),
  authorised_by_decision_id uuid references app.decision(id),
  created_by     uuid not null references app.user(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (authorised_by_task_id is not null or authorised_by_decision_id is not null)
);

create table app.filing_item (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  filing_id      uuid not null references app.filing(id) on delete cascade,
  document_id    uuid not null references app.document(id),
  document_version_id uuid not null references app.document_version(id),
  role           text not null check (role in ('main','annexure','affidavit','fee_receipt','other')),
  ordinal        int not null default 0,
  unique (filing_id, document_version_id, role)
);

-- ---------------------------------------------------------------------------
-- Knowledge and research
-- ---------------------------------------------------------------------------
create table app.source (
  id             uuid primary key default gen_random_uuid(),
  url            text,
  publisher      text,
  retrieved_at   timestamptz not null default now(),
  content_sha256 text,
  reliability    text not null default 'official' check (reliability in
                   ('official','semi_official','commentary','unverified')),
  licence_note   text,
  created_at     timestamptz not null default now()
);

create table app.authority (
  id             uuid primary key default gen_random_uuid(),
  kind           text not null check (kind in
                   ('statute','judgment','court_rule','notification','circular','commentary','other')),
  citation_text  text not null,
  title          text not null,
  court          text,
  year           int,
  canonical_url  text,
  source_id      uuid references app.source(id),
  status         text not null default 'unverified' check (status in
                   ('unverified','verified','stale','overruled','repealed')),
  verified_at    timestamptz,
  verified_by    uuid references app.user(id),
  created_at     timestamptz not null default now()
);
create index authority_citation_trgm on app.authority using gin (citation_text gin_trgm_ops);
create index authority_year_court on app.authority (year, court);

create table app.authority_version (
  id             uuid primary key default gen_random_uuid(),
  authority_id   uuid not null references app.authority(id) on delete cascade,
  version_label  text not null,
  effective_from date not null,
  effective_to   date,
  text_sha256    text,
  source_id      uuid references app.source(id),
  created_at     timestamptz not null default now(),
  unique (authority_id, version_label),
  check (effective_to is null or effective_to >= effective_from)
);

create table app.citation (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  document_version_id uuid not null references app.document_version(id) on delete cascade,
  anchor_key     text,
  authority_id   uuid not null references app.authority(id),
  authority_version_id uuid references app.authority_version(id),
  pinpoint       text,
  quoted_text    text,
  source_text_hash text,
  status         text not null default 'unverified' check (status in
                   ('unverified','verified','failed','stale','disputed')),
  checked_at     timestamptz,
  checked_by     uuid references app.user(id),
  check_note     text,
  created_at     timestamptz not null default now(),
  unique (document_version_id, anchor_key, authority_id, pinpoint)
);

create table app.research_query (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  question       text not null,
  scope          jsonb not null default '{}'::jsonb,
  status         text not null default 'open' check (status in ('open','answered','abandoned')),
  created_by     uuid not null references app.user(id),
  created_at     timestamptz not null default now()
);

create table app.research_result (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  query_id       uuid not null references app.research_query(id) on delete cascade,
  authority_id   uuid references app.authority(id),
  proposition    text not null,
  quote          text,
  pinpoint       text,
  relevance      text not null default 'support' check (relevance in ('support','adverse','context')),
  status         text not null default 'proposed' check (status in ('proposed','accepted','rejected')),
  decided_by     uuid references app.user(id),
  decided_at     timestamptz,
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Facts and evidence
-- ---------------------------------------------------------------------------
create table app.fact (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  statement      text not null,
  occurred_at    date,
  status         text not null default 'alleged' check (status in
                   ('alleged','admitted','disputed','proved','disproved')),
  source_kind    text check (source_kind in ('document','testimony','party','court','inference')),
  source_text_hash text,
  created_by     uuid references app.user(id),
  verified_by    uuid references app.user(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index fact_matter on app.fact (matter_id, occurred_at);

create table app.evidence (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  kind           text not null check (kind in ('document','testimony','object','electronic','other')),
  description    text not null,
  document_id    uuid references app.document(id),
  custody        text,
  status         text not null default 'collected' check (status in
                   ('collected','submitted','admitted','rejected','returned')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index evidence_matter on app.evidence (matter_id);

create table app.fact_evidence (
  fact_id        uuid not null references app.fact(id) on delete cascade,
  evidence_id    uuid not null references app.evidence(id) on delete cascade,
  matter_id      uuid not null references app.matter(id) on delete cascade,
  relation       text not null check (relation in ('supports','contradicts','context')),
  weight         smallint check (weight between 1 and 5),
  note           text,
  primary key (fact_id, evidence_id)
);

-- Fact positions: append-only and attributed. fact.status is a derived
-- summary (court > advocate > party); positions supersede, never overwrite.
create table app.fact_position (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  fact_id        uuid not null references app.fact(id) on delete cascade,
  position       text not null check (position in
                   ('asserted','admitted','disputed','found_proved','found_disproved','rejected')),
  source_kind    text not null check (source_kind in ('party','advocate','court')),
  basis_ref      text,
  order_id       uuid references app."order"(id),
  recorded_by    uuid not null references app.user(id),
  recorded_at    timestamptz not null default now(),
  superseded_by  uuid references app.fact_position(id)
);
create index fact_position_fact on app.fact_position (fact_id, recorded_at desc);

-- Evidence status: three independent axes (authenticity, admissibility,
-- inclusion), each an attributed event. evidence.status remains as a
-- derived summary. A court finding is an event referencing the order.
create table app.evidence_status (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  evidence_id    uuid not null references app.evidence(id) on delete cascade,
  axis           text not null check (axis in ('authenticity','admissibility','inclusion')),
  value          text not null,
  source_kind    text not null check (source_kind in ('advocate','court')),
  order_id       uuid references app."order"(id),
  note           text,
  recorded_by    uuid not null references app.user(id),
  recorded_at    timestamptz not null default now(),
  superseded_by  uuid references app.evidence_status(id)
);
create index evidence_status_evidence on app.evidence_status (evidence_id, axis, recorded_at desc);

-- Exhibits: the use of an evidence record in a proceeding. The number is
-- assigned by the advocate at marking — a use, not a property of the thing.
create table app.exhibit (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  proceeding_id  uuid not null references app.proceeding(id) on delete cascade,
  evidence_id    uuid not null references app.evidence(id) on delete cascade,
  exhibit_no     text not null,
  as_filed_role  text,
  marked_on      date,
  order_id       uuid references app."order"(id),
  status         text not null default 'marked' check (status in
                   ('marked','expunged','withdrawn','returned')),
  created_by     uuid not null references app.user(id),
  created_at     timestamptz not null default now(),
  unique (proceeding_id, exhibit_no)
);
create index exhibit_evidence on app.exhibit (evidence_id);

-- Registry identity events: a transferred or renumbered case is the same
-- proceeding; identity changes are append-only events with sources.
create table app.registry_event (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  proceeding_id  uuid not null references app.proceeding(id) on delete cascade,
  kind           text not null check (kind in ('registered','transferred','renumbered')),
  value          text not null,
  effective_on   date not null,
  source_ref     text,
  order_id       uuid references app."order"(id),
  created_by     uuid not null references app.user(id),
  created_at     timestamptz not null default now()
);
create index registry_event_proceeding on app.registry_event (proceeding_id, effective_on desc);

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------
create table app.rule_instrument (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  kind           text not null check (kind in
                   ('act','court_rules','practice_direction','notification','e_filing_spec','circular','other')),
  jurisdiction   text,
  forum_id       uuid references app.forum(id),
  effective_from date not null,
  effective_to   date,
  source_id      uuid not null references app.source(id),
  supersedes_id  uuid references app.rule_instrument(id),
  status         text not null default 'draft' check (status in ('draft','published','superseded','withdrawn')),
  verified_by    uuid references app.user(id),
  verified_at    timestamptz,
  created_at     timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from)
);

create table app.format_rule (
  id             uuid primary key default gen_random_uuid(),
  instrument_id  uuid not null references app.rule_instrument(id) on delete cascade,
  rule_key       text not null,
  clause_ref     text,
  scope          jsonb not null default '{}'::jsonb,
  spec           jsonb not null,
  severity       text not null default 'error' check (severity in ('error','warning','info')),
  created_at     timestamptz not null default now(),
  unique (instrument_id, rule_key, clause_ref)
);
create index format_rule_scope on app.format_rule using gin (scope);

-- Guideline pipeline (RD-45): one fetched, content-addressed snapshot of an
-- official rule source. Change detection compares content hashes; extraction
-- may be model-assisted but only a human verifies and publishes. A snapshot
-- without a verifier is never resolvable.
create table app.rule_snapshot (
  id             uuid primary key default gen_random_uuid(),
  instrument_id  uuid references app.rule_instrument(id) on delete cascade,
  source_id      uuid not null references app.source(id),
  fetched_at     timestamptz not null default now(),
  content_sha256 text not null,
  blob_sha256    text references app.blob(sha256),
  parse_status   text not null default 'pending' check (parse_status in
                   ('pending','parsed','parse_failed','rejected')),
  extracted_rules jsonb not null default '[]'::jsonb,
  diff_from_id   uuid references app.rule_snapshot(id),
  reviewed_by    uuid references app.user(id),
  reviewed_at    timestamptz,
  created_at     timestamptz not null default now()
);
create index rule_snapshot_instrument on app.rule_snapshot (instrument_id, fetched_at desc);

-- ---------------------------------------------------------------------------
-- Gates, readiness, retrieval packets and egress
-- ---------------------------------------------------------------------------
create table app.gate (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  kind           text not null check (kind in
                   ('matter_open','document_approve','filing_ready','rule_publish','access_grant','deletion')),
  subject_type   text not null,
  subject_id     uuid not null,
  rule_ref       text,
  evidence       jsonb not null default '{}'::jsonb,
  snapshot_hash  text not null,
  status         text not null default 'open' check (status in
                   ('open','cleared','waived','blocked','expired')),
  decided_by     uuid references app.user(id),
  decided_at     timestamptz,
  expires_at     timestamptz,
  note           text,
  created_at     timestamptz not null default now()
);
create unique index gate_one_open on app.gate (kind, subject_type, subject_id)
  where status = 'open';
create index gate_subject on app.gate (subject_type, subject_id);

create table app.verification_run (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  subject_type   text not null check (subject_type in ('document_version','filing','retrieval_packet')),
  subject_id     uuid not null,
  subject_hash   text not null,
  kind           text not null check (kind in ('citation','format','quote','cross_reference','integrity','completion','full')),
  status         text not null check (status in ('pending','passed','failed','unconfirmed')),
  findings       jsonb not null default '[]'::jsonb,
  verified_by    uuid references app.user(id),
  verified_at    timestamptz not null default now(),
  created_at     timestamptz not null default now()
);
create index verification_subject on app.verification_run
  (subject_type, subject_id, verified_at desc);

create table app.retrieval_packet (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  purpose        text not null,
  recipient      text not null,
  schema_version text not null default '1',
  redaction_policy text not null default 'redacted' check (redaction_policy in ('redacted','unredacted')),
  manifest       jsonb not null default '{}'::jsonb,
  content_hash   text not null,
  blob_sha256    text references app.blob(sha256),
  status         text not null default 'draft' check (status in ('draft','approved','exported','expired','revoked')),
  expires_at     timestamptz,
  created_by     uuid not null references app.user(id),
  approved_by    uuid references app.user(id),
  created_at     timestamptz not null default now()
);
create index retrieval_packet_matter on app.retrieval_packet (matter_id, created_at desc);

create table app.egress_policy (
  id             uuid primary key default gen_random_uuid(),
  capability_id  text not null,
  host           text not null,
  path_pattern   text not null default '/*',
  method         text not null default 'GET' check (method in ('GET','POST','PUT','PATCH','DELETE')),
  created_by     uuid not null references app.user(id),
  created_at     timestamptz not null default now(),
  unique (capability_id, host, path_pattern, method)
);

-- ---------------------------------------------------------------------------
-- Capabilities: bundles, skills, playbooks
-- ---------------------------------------------------------------------------
create table app.bundle (
  id             uuid primary key default gen_random_uuid(),
  key            text not null unique,
  name           text not null,
  owner          text not null,
  description    text,
  created_at     timestamptz not null default now()
);

create table app.bundle_version (
  id             uuid primary key default gen_random_uuid(),
  bundle_id      uuid not null references app.bundle(id) on delete cascade,
  version        text not null,
  instructions   text not null,
  tools          jsonb not null default '[]'::jsonb,
  subagent_tools jsonb not null default '[]'::jsonb,
  scope          jsonb not null default '{}'::jsonb,
  budget         jsonb not null default '{}'::jsonb,
  eval_suite     jsonb not null default '{}'::jsonb,
  content_hash   text not null,
  status         text not null default 'draft' check (status in
                   ('draft','eval_passed','published','retired','blocked')),
  published_at   timestamptz,
  created_at     timestamptz not null default now(),
  unique (bundle_id, version)
);

-- One table per concept; each version is a row (RD-42). A run pins the exact row.
create table app.skill (
  id               uuid primary key default gen_random_uuid(),
  key              text not null,
  version          text not null,
  name             text not null,
  description      text,
  content          text not null,
  inputs_schema    jsonb not null default '{}'::jsonb,
  output_schema    jsonb not null default '{}'::jsonb,
  permitted_tools  jsonb not null default '[]'::jsonb,
  checks           jsonb not null default '[]'::jsonb,
  approval_points  jsonb not null default '[]'::jsonb,
  scope            jsonb not null default '{}'::jsonb,
  tests            jsonb not null default '[]'::jsonb,
  content_hash     text not null,
  status           text not null default 'published' check (status in ('draft','published','retired')),
  created_at       timestamptz not null default now(),
  unique (key, version)
);

create table app.playbook (
  id               uuid primary key default gen_random_uuid(),
  key              text not null,
  version          text not null,
  name             text not null,
  description      text,
  steps            jsonb not null,
  gates            jsonb not null default '[]'::jsonb,
  roles            jsonb not null default '[]'::jsonb,
  scope            jsonb not null default '{}'::jsonb,
  content_hash     text not null,
  status           text not null default 'draft' check (status in ('draft','published','retired')),
  created_at       timestamptz not null default now(),
  unique (key, version)
);

-- ---------------------------------------------------------------------------
-- Execution
-- ---------------------------------------------------------------------------
create table app.conversation (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  user_id        uuid not null references app.user(id),
  title          text,
  status         text not null default 'open' check (status in ('open','closed','archived')),
  created_at     timestamptz not null default now(),
  last_active_at timestamptz not null default now()
);
create index conversation_matter on app.conversation (matter_id, last_active_at desc);
create index conversation_user on app.conversation (user_id, last_active_at desc);

create table app.playbook_run (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  playbook_id    uuid not null references app.playbook(id),
  status         text not null default 'pending' check (status in
                   ('pending','running','waiting_human','waiting_external','completed','failed','cancelled')),
  current_step_key text,
  started_by     uuid not null references app.user(id),
  started_at     timestamptz,
  ended_at       timestamptz,
  created_at     timestamptz not null default now()
);
create index playbook_run_matter on app.playbook_run (matter_id, status);

create table app.step_run (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  playbook_run_id uuid not null references app.playbook_run(id) on delete cascade,
  step_key       text not null,
  kind           text not null check (kind in ('agent','check','human','external')),
  status         text not null default 'pending' check (status in
                   ('pending','running','waiting_human','waiting_external','completed','failed','skipped')),
  assigned_to    uuid references app.user(id),
  input          jsonb not null default '{}'::jsonb,
  output         jsonb not null default '{}'::jsonb,
  approval_id    uuid references app.approval(id),
  error_code     text,
  started_at     timestamptz,
  ended_at       timestamptz,
  unique (playbook_run_id, step_key)
);

create table app.context_package (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  scope          jsonb not null default '{}'::jsonb,
  budget         jsonb not null default '{}'::jsonb,
  manifest       jsonb not null,
  content_hash   text not null,
  created_at     timestamptz not null default now()
);

create table app.agent_run (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  conversation_id uuid references app.conversation(id) on delete set null,
  step_run_id    uuid references app.step_run(id) on delete set null,
  parent_run_id  uuid references app.agent_run(id) on delete cascade,
  depth          smallint not null default 0 check (depth between 0 and 4),
  kind           text not null default 'primary' check (kind in ('primary','spawn','fork','map','verify','background')),
  user_id        uuid not null references app.user(id),
  status         text not null default 'queued' check (status in
                   ('queued','scoped','running','waiting_approval','completed','failed','cancelled')),
  model          text,
  provider       text,
  context_package_id uuid references app.context_package(id),
  budget         jsonb not null default '{}'::jsonb,
  tokens_in      bigint not null default 0,
  tokens_out     bigint not null default 0,
  cost_usd       numeric(12,6) not null default 0,
  trace_id       text,
  started_at     timestamptz,
  ended_at       timestamptz
);
create index agent_run_matter on app.agent_run (matter_id, started_at desc);
create index agent_run_parent on app.agent_run (parent_run_id);
create index agent_run_status on app.agent_run (status);

create table app.agent_event (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  run_id         uuid not null references app.agent_run(id) on delete cascade,
  seq            int not null,
  kind           text not null check (kind in ('model','tool','approval','subagent','error')),
  capability_id  text,
  model          text,
  tokens_in      int,
  tokens_out     int,
  cost_usd       numeric(12,6),
  latency_ms     int,
  payload        jsonb not null default '{}'::jsonb,
  payload_hash   text,
  created_at     timestamptz not null default now(),
  unique (run_id, seq)
);

create table app.run_bundle (
  run_id         uuid not null references app.agent_run(id) on delete cascade,
  matter_id      uuid not null references app.matter(id) on delete cascade,
  bundle_version_id uuid not null references app.bundle_version(id),
  order_no       int not null default 0,
  primary key (run_id, bundle_version_id)
);

create table app.session (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references app.user(id) on delete cascade,
  device_id      uuid,
  token_hash     text not null unique,
  ip             inet,
  user_agent     text,
  created_at     timestamptz not null default now(),
  last_seen_at   timestamptz not null default now(),
  expires_at     timestamptz not null,
  revoked_at     timestamptz
);

create table app.device (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references app.user(id) on delete cascade,
  name           text not null,
  public_key     text not null,
  last_seen_at   timestamptz,
  revoked_at     timestamptz,
  created_at     timestamptz not null default now()
);

alter table app.session
  add constraint session_device_fk
  foreign key (device_id) references app.device(id);

-- ---------------------------------------------------------------------------
-- V1 additions: collaboration, classification, forum adapters, browser,
-- corpus, case law, library, research studio and workflows.
-- The Matter is the only shared boundary; there is no proceeding relation.
-- ---------------------------------------------------------------------------

alter table app.proceeding
  add column if not exists impugned_order_id uuid references app."order"(id) on delete set null,
  add column if not exists originating_proceeding_id uuid references app.proceeding(id) on delete set null,
  add column if not exists jurisdiction_basis text,
  add column if not exists governing_date date,
  add column if not exists detail jsonb not null default '{}'::jsonb;

alter table app.document_version
  add column if not exists editing_session_id uuid;

alter table app.document_version
  drop constraint if exists document_version_source_check;
alter table app.document_version
  add constraint document_version_source_check check (source in
    ('upload','agent_generated','editor_save','import','template','export'));

alter table app.agent_run
  add column if not exists node_id uuid,
  add column if not exists task_id uuid references app.task(id) on delete set null,
  add column if not exists lease_id text,
  add column if not exists lease_expires_at timestamptz,
  add column if not exists heartbeat_at timestamptz,
  add column if not exists attempt int not null default 1,
  add column if not exists step_store_run_id text;

alter table app.agent_run drop constraint if exists agent_run_depth_check;
alter table app.agent_run add constraint agent_run_depth_check check (depth between 0 and 2);
alter table app.agent_run drop constraint if exists agent_run_status_check;
alter table app.agent_run add constraint agent_run_status_check check (status in
  ('queued','scoped','running','waiting_approval','suspended','uncertain','completed','failed','cancelled'));

alter table app.agent_event
  add column if not exists operation_id text,
  add column if not exists effect_status text
    check (effect_status in ('started','completed','failed','unknown'));
create unique index if not exists agent_event_operation
  on app.agent_event (run_id, operation_id) where operation_id is not null;

alter table app.context_package
  add column if not exists run_id uuid references app.agent_run(id) on delete cascade;

create table app.resource_grant (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  resource_type  text not null check (resource_type in ('document')),
  resource_id    uuid not null,
  subject_user_id uuid not null references app.user(id) on delete cascade,
  level          text not null check (level in ('view','comment','edit')),
  granted_by     uuid not null references app.user(id),
  created_at     timestamptz not null default now(),
  revoked_at     timestamptz,
  unique (resource_type, resource_id, subject_user_id)
);
create index resource_grant_lookup on app.resource_grant
  (resource_type, resource_id, subject_user_id) where revoked_at is null;

create table app.message (
  id              uuid primary key default gen_random_uuid(),
  matter_id       uuid not null references app.matter(id) on delete cascade,
  conversation_id uuid not null references app.conversation(id) on delete cascade,
  seq             int not null,
  author_type     text not null check (author_type in ('user','agent')),
  author_user_id  uuid references app.user(id),
  author_run_id   uuid references app.agent_run(id),
  reply_to_id     uuid references app.message(id),
  client_message_id text,
  body            text not null,
  created_at      timestamptz not null default now(),
  unique (conversation_id, seq),
  check ((author_type = 'user') = (author_user_id is not null)),
  check ((author_type = 'agent') = (author_run_id is not null))
);

create table app.task_document (
  id          uuid primary key default gen_random_uuid(),
  matter_id   uuid not null references app.matter(id) on delete cascade,
  task_id     uuid not null references app.task(id) on delete cascade,
  document_id uuid not null references app.document(id) on delete cascade,
  created_by  uuid not null references app.user(id),
  created_at  timestamptz not null default now(),
  unique (task_id, document_id)
);

create table app.editing_session (
  id              uuid primary key default gen_random_uuid(),
  matter_id       uuid not null references app.matter(id) on delete cascade,
  document_id     uuid not null references app.document(id) on delete cascade,
  base_version_id uuid not null references app.document_version(id),
  provider_key    text not null unique,
  provider        text not null default 'euro_office' check (provider in ('euro_office')),
  status          text not null default 'opening' check (status in
                    ('opening','active','closing','closed','failed','revoked','expired')),
  opened_by       uuid not null references app.user(id),
  opened_at       timestamptz not null default now(),
  last_heartbeat_at timestamptz,
  closed_at       timestamptz,
  result_version_id uuid references app.document_version(id),
  takeover_requested_by uuid references app.user(id),
  takeover_requested_at timestamptz,
  takeover_approved_by uuid references app.user(id),
  takeover_approved_at timestamptz,
  failure_code    text
);
create unique index editing_session_active on app.editing_session (document_id)
  where status in ('opening','active','closing');
create index editing_session_document on app.editing_session (document_id, opened_at desc);

alter table app.document_version
  add constraint document_version_editing_session_fk
  foreign key (editing_session_id) references app.editing_session(id) on delete set null;

create table app.document_proposal (
  id              uuid primary key default gen_random_uuid(),
  matter_id       uuid not null references app.matter(id) on delete cascade,
  document_id     uuid not null references app.document(id) on delete cascade,
  base_version_id uuid not null references app.document_version(id),
  base_hash       text not null,
  anchor_key      text,
  expected_text_hash text,
  operation       text not null check (operation in ('replace','insert','delete','comment')),
  patch_sha256    text,
  proposed_by_run_id uuid references app.agent_run(id),
  proposed_by_user_id uuid references app.user(id),
  status          text not null default 'proposed' check (status in
                    ('proposed','rebased','applied','rejected','stale','needs_human','superseded')),
  applied_version_id uuid references app.document_version(id),
  reviewed_by     uuid references app.user(id),
  reviewed_at     timestamptz,
  idempotency_key text unique,
  created_at      timestamptz not null default now()
);
create index document_proposal_document on app.document_proposal (document_id, status);

create table app.execution_node (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid references app.user(id) on delete set null,
  device_id      uuid references app.device(id) on delete set null,
  kind           text not null check (kind in ('desktop','server_worker','shared')),
  name           text not null,
  capabilities   jsonb not null default '{}'::jsonb,
  status         text not null default 'active' check (status in ('active','offline','revoked')),
  last_heartbeat_at timestamptz,
  registered_at  timestamptz not null default now(),
  revoked_at     timestamptz
);

alter table app.agent_run
  add constraint agent_run_node_fk
  foreign key (node_id) references app.execution_node(id) on delete set null;

create table app.notification (
  id            uuid primary key default gen_random_uuid(),
  matter_id     uuid references app.matter(id) on delete cascade,
  recipient_user_id uuid not null references app.user(id) on delete cascade,
  kind          text not null,
  subject_type  text,
  subject_id    uuid,
  payload       jsonb not null default '{}'::jsonb,
  read_at       timestamptz,
  created_at    timestamptz not null default now()
);
create index notification_recipient on app.notification (recipient_user_id, created_at desc);

create table app.notification_delivery (
  id             uuid primary key default gen_random_uuid(),
  notification_id uuid not null references app.notification(id) on delete cascade,
  matter_id      uuid references app.matter(id) on delete cascade,
  channel        text not null,
  destination    text,
  status         text not null default 'pending' check (status in ('pending','sent','failed')),
  attempts       int not null default 0,
  next_attempt_at timestamptz,
  sent_at        timestamptz
);

create table app.job (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid references app.matter(id) on delete cascade,
  kind           text not null,
  payload        jsonb not null default '{}'::jsonb,
  status         text not null default 'queued' check (status in
                    ('queued','running','done','failed','cancelled')),
  attempts       int not null default 0,
  run_at         timestamptz not null default now(),
  locked_by      text,
  locked_at      timestamptz,
  lease_expires_at timestamptz,
  idempotency_key text unique,
  created_at     timestamptz not null default now()
);
create index job_ready on app.job (status, run_at) where status = 'queued';

create table app.classification (
  id              uuid primary key default gen_random_uuid(),
  matter_id       uuid not null references app.matter(id) on delete cascade,
  subject_type    text not null check (subject_type in ('matter','proceeding')),
  subject_id      uuid not null,
  schema_key      text not null,
  schema_version  int not null default 1,
  fields          jsonb not null default '{}'::jsonb,
  evidence        jsonb not null default '{}'::jsonb,
  status          text not null default 'proposed' check (status in
                    ('proposed','confirmed','superseded','rejected')),
  proposed_by_run_id uuid references app.agent_run(id),
  confirmed_by    uuid references app.user(id),
  confirmed_at    timestamptz,
  created_at      timestamptz not null default now()
);
create unique index classification_confirmed on app.classification (subject_type, subject_id)
  where status = 'confirmed';

create table app.forum_adapter (
  id             uuid primary key default gen_random_uuid(),
  forum_id       uuid not null references app.forum(id) on delete cascade,
  name           text not null,
  kind           text not null,
  capabilities   jsonb not null default '{}'::jsonb,
  source_url     text,
  status         text not null default 'active' check (status in ('active','disabled','failed')),
  last_sync_at   timestamptz,
  created_at     timestamptz not null default now(),
  unique (forum_id, name)
);

create table app.browser_session (
  id              uuid primary key default gen_random_uuid(),
  matter_id       uuid not null references app.matter(id) on delete cascade,
  user_id         uuid not null references app.user(id),
  kind            text not null check (kind in ('user','agent')),
  status          text not null default 'open' check (status in ('open','closed','revoked')),
  controller_user_id uuid references app.user(id),
  controller_run_id uuid references app.agent_run(id),
  policy          jsonb not null default '{}'::jsonb,
  opened_at       timestamptz not null default now(),
  ended_at        timestamptz
);

create table app.browser_control_lease (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid not null references app.browser_session(id) on delete cascade,
  matter_id   uuid not null references app.matter(id) on delete cascade,
  holder_user_id uuid not null references app.user(id),
  holder_run_id uuid references app.agent_run(id),
  expires_at  timestamptz not null,
  created_at  timestamptz not null default now()
);
create unique index browser_control_one on app.browser_control_lease (session_id);

create table app.legal_instrument (
  id             uuid primary key default gen_random_uuid(),
  source_id      uuid not null references app.source(id),
  kind           text not null check (kind in
                    ('statute','court_rules','regulation','notification','practice_direction','manual','other')),
  title          text not null,
  jurisdiction   text,
  forum_id       uuid references app.forum(id),
  status         text not null default 'draft' check (status in ('draft','published','retired')),
  created_at     timestamptz not null default now()
);

create table app.instrument_version (
  id             uuid primary key default gen_random_uuid(),
  instrument_id  uuid not null references app.legal_instrument(id) on delete cascade,
  version_no     int not null,
  effective_from date,
  effective_to   date,
  text_hash      text,
  supersedes_id  uuid references app.instrument_version(id),
  verified_by    uuid references app.user(id),
  verified_at    timestamptz,
  created_at     timestamptz not null default now(),
  unique (instrument_id, version_no)
);

create table app.instrument_snapshot (
  id             uuid primary key default gen_random_uuid(),
  instrument_version_id uuid not null references app.instrument_version(id) on delete cascade,
  content_sha256 text not null,
  blob_sha256    text not null references app.blob(sha256),
  fetched_at     timestamptz not null default now(),
  diff_from_id   uuid references app.instrument_snapshot(id)
);

create table app.provision (
  id             uuid primary key default gen_random_uuid(),
  instrument_version_id uuid not null references app.instrument_version(id) on delete cascade,
  provision_key  text not null,
  heading        text,
  text           text not null,
  anchor         text,
  unique (instrument_version_id, provision_key)
);

create table app.judgment (
  id             uuid primary key default gen_random_uuid(),
  source_id      uuid not null references app.source(id),
  forum_id       uuid references app.forum(id),
  case_number    text,
  title          text not null,
  decided_on     date,
  status         text not null default 'draft' check (status in ('draft','published','retired')),
  created_at     timestamptz not null default now()
);

create table app.judgment_version (
  id             uuid primary key default gen_random_uuid(),
  judgment_id    uuid not null references app.judgment(id) on delete cascade,
  version_no     int not null,
  text_hash      text,
  treatment      text,
  supersedes_id  uuid references app.judgment_version(id),
  verified_by    uuid references app.user(id),
  verified_at    timestamptz,
  created_at     timestamptz not null default now(),
  unique (judgment_id, version_no)
);

create table app.judgment_snapshot (
  id             uuid primary key default gen_random_uuid(),
  judgment_version_id uuid not null references app.judgment_version(id) on delete cascade,
  content_sha256 text not null,
  blob_sha256    text not null references app.blob(sha256),
  fetched_at     timestamptz not null default now()
);

create table app.library_item (
  id             uuid primary key default gen_random_uuid(),
  kind           text not null check (kind in ('template','precedent','checklist','guidance')),
  title          text not null,
  owner_user_id  uuid references app.user(id),
  status         text not null default 'draft' check (status in ('draft','published','retired')),
  created_at     timestamptz not null default now()
);

create table app.library_version (
  id             uuid primary key default gen_random_uuid(),
  item_id        uuid not null references app.library_item(id) on delete cascade,
  version_no     int not null,
  content_hash   text,
  blob_sha256    text references app.blob(sha256),
  published_by   uuid references app.user(id),
  published_at   timestamptz,
  unique (item_id, version_no)
);

create table app.library_grant (
  id             uuid primary key default gen_random_uuid(),
  item_id        uuid not null references app.library_item(id) on delete cascade,
  subject_user_id uuid references app.user(id) on delete cascade,
  subject_role   text,
  level          text not null default 'view' check (level in ('view','use')),
  granted_by     uuid not null references app.user(id),
  created_at     timestamptz not null default now(),
  check ((subject_user_id is null) <> (subject_role is null))
);

create table app.research_project (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  title          text not null,
  created_by     uuid not null references app.user(id),
  status         text not null default 'open' check (status in ('open','closed','archived')),
  created_at     timestamptz not null default now()
);

create table app.research_plan (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  project_id     uuid not null references app.research_project(id) on delete cascade,
  version_no     int not null,
  plan           jsonb not null default '{}'::jsonb,
  status         text not null default 'draft' check (status in ('draft','approved','superseded')),
  approved_by    uuid references app.user(id),
  approved_at    timestamptz,
  unique (project_id, version_no)
);

create table app.workflow_definition (
  id             uuid primary key default gen_random_uuid(),
  key            text not null,
  kind           text not null default 'playbook' check (kind in ('playbook','automation','research','other')),
  status         text not null default 'draft' check (status in ('draft','published','retired')),
  owner_user_id  uuid references app.user(id),
  created_at     timestamptz not null default now(),
  unique (key)
);

create table app.workflow_version (
  id             uuid primary key default gen_random_uuid(),
  definition_id  uuid not null references app.workflow_definition(id) on delete cascade,
  version_no     int not null,
  graph_spec     jsonb not null,
  content_hash   text not null,
  published_by   uuid references app.user(id),
  published_at   timestamptz,
  unique (definition_id, version_no)
);

create table app.workflow_run (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  version_id     uuid not null references app.workflow_version(id),
  status         text not null default 'pending' check (status in
                    ('pending','running','waiting_human','waiting_external','completed','failed','cancelled')),
  started_by     uuid not null references app.user(id),
  started_at     timestamptz,
  ended_at       timestamptz,
  created_at     timestamptz not null default now()
);

create table app.workflow_step (
  id             uuid primary key default gen_random_uuid(),
  matter_id      uuid not null references app.matter(id) on delete cascade,
  run_id         uuid not null references app.workflow_run(id) on delete cascade,
  node_key       text not null,
  status         text not null default 'pending' check (status in
                    ('pending','running','waiting_human','waiting_external','completed','failed','skipped')),
  assigned_to    uuid references app.user(id),
  input          jsonb not null default '{}'::jsonb,
  output         jsonb not null default '{}'::jsonb,
  approval_id    uuid references app.approval(id),
  error_code     text,
  started_at     timestamptz,
  ended_at       timestamptz,
  unique (run_id, node_key)
);

-- ---------------------------------------------------------------------------
-- Audit (append-only, hash-chained)
-- ---------------------------------------------------------------------------
create table audit.audit_event (
  seq            bigint generated always as identity primary key,
  id             uuid not null default gen_random_uuid(),
  at             timestamptz not null default now(),
  actor_type     text not null check (actor_type in ('user','agent','system','service')),
  actor_id       uuid,
  actor_ref      text,
  trigger_type   text not null default 'direct' check (trigger_type in
                   ('direct','delegation','schedule')),
  run_id         uuid references app.agent_run(id) on delete set null,
  initiating_user_id uuid references app.user(id),
  approval_status text check (approval_status in
                   ('pending','approved','rejected','expired','stale')),
  approver_id    uuid references app.user(id),
  action         text not null,
  subject_type   text not null,
  subject_id     uuid,
  matter_id      uuid,
  request_id     text,
  payload        jsonb not null default '{}'::jsonb,
  prev_hash      bytea,
  hash           bytea not null
);

create or replace function audit.append_event() returns trigger
language plpgsql
set search_path = audit, public, pg_temp
as $$
declare
  v_prev bytea;
  v_body text;
begin
  perform pg_advisory_xact_lock(hashtext('audit.audit_event'));
  select hash into v_prev from audit.audit_event order by seq desc limit 1;
  v_body := concat_ws('|',
    coalesce(new.seq::text,''), coalesce(new.id::text,''), coalesce(new.at::text,''),
    coalesce(new.actor_type,''), coalesce(new.actor_id::text,''), coalesce(new.actor_ref,''),
    coalesce(new.trigger_type,''), coalesce(new.run_id::text,''),
    coalesce(new.initiating_user_id::text,''), coalesce(new.approval_status,''),
    coalesce(new.approver_id::text,''),
    new.action, new.subject_type, coalesce(new.subject_id::text,''),
    coalesce(new.matter_id::text,''), coalesce(new.request_id,''),
    new.payload::text);
  new.prev_hash := v_prev;
  new.hash := public.digest(coalesce(v_prev, ''::bytea) || convert_to(v_body, 'UTF8'), 'sha256');
  return new;
end $$;

create trigger audit_event_chain
  before insert on audit.audit_event
  for each row execute function audit.append_event();

drop function if exists audit.append(text,uuid,text,text,uuid,uuid,text,jsonb);

create or replace function audit.append(
  p_actor_type text, p_actor_id uuid, p_action text,
  p_subject_type text, p_subject_id uuid, p_matter_id uuid,
  p_request_id text, p_payload jsonb,
  p_actor_ref text default null,
  p_trigger_type text default 'direct',
  p_run_id uuid default null,
  p_initiating_user_id uuid default null,
  p_approval_status text default null,
  p_approver_id uuid default null
) returns bigint
language sql security definer
set search_path = audit, pg_temp as $$
  insert into audit.audit_event
    (actor_type, actor_id, actor_ref, trigger_type, run_id, initiating_user_id,
     approval_status, approver_id, action, subject_type, subject_id, matter_id,
     request_id, payload)
  values (p_actor_type, p_actor_id, p_actor_ref, p_trigger_type, p_run_id,
          p_initiating_user_id, p_approval_status, p_approver_id, p_action,
          p_subject_type, p_subject_id, p_matter_id, p_request_id,
          coalesce(p_payload,'{}'::jsonb))
  returning seq
$$;

revoke all on function audit.append(text,uuid,text,text,uuid,uuid,text,jsonb,text,text,uuid,uuid,text,uuid) from public;
grant execute on function audit.append(text,uuid,text,text,uuid,uuid,text,jsonb,text,text,uuid,uuid,text,uuid) to maverick_app;
alter function audit.append(text,uuid,text,text,uuid,uuid,text,jsonb,text,text,uuid,uuid,text,uuid) owner to maverick_owner;
alter function audit.append_event() owner to maverick_owner;

-- ---------------------------------------------------------------------------
-- Immutability and touch triggers
-- ---------------------------------------------------------------------------
create trigger document_version_immutable
  before update or delete on app.document_version
  for each row execute function app.reject_mutation();

create trigger audit_event_immutable
  before update or delete on audit.audit_event
  for each row execute function app.reject_mutation();

create trigger document_touch before update on app.document
  for each row execute function app.touch_updated_at();
create trigger matter_touch before update on app.matter
  for each row execute function app.touch_updated_at();
create trigger task_touch before update on app.task
  for each row execute function app.touch_updated_at();
create trigger deadline_touch before update on app.deadline
  for each row execute function app.touch_updated_at();
create trigger proceeding_touch before update on app.proceeding
  for each row execute function app.touch_updated_at();
create trigger proceeding_application_touch before update on app.proceeding_application
  for each row execute function app.touch_updated_at();

-- Application tree guards (FD-15): the parent must exist, sit in the same
-- matter, and be shallower than the cap; the denormalised proceeding link
-- must match the parent chain. The parent link is frozen on update, so no
-- cycle can ever be created by an UPDATE; an INSERT cannot create one
-- because the parent must already exist.
create or replace function app.check_application_parent() returns trigger
language plpgsql as $$
declare
  v_parent app.proceeding_application%rowtype;
  v_matter uuid;
begin
  if new.proceeding_id is not null then
    select matter_id into v_matter from app.proceeding
      where id = new.proceeding_id;
    if v_matter is distinct from new.matter_id then
      raise exception 'application proceeding belongs to another matter'
        using errcode = '42501';
    end if;
  end if;
  if new.parent_application_id is not null then
    select * into v_parent from app.proceeding_application
      where id = new.parent_application_id;
    if not found then
      raise exception 'application parent not found'
        using errcode = '23503';
    end if;
    if v_parent.matter_id <> new.matter_id then
      raise exception 'application parent belongs to another matter'
        using errcode = '42501';
    end if;
    if v_parent.depth >= 6 then
      raise exception 'application nesting deeper than 6'
        using errcode = '23514';
    end if;
    new.depth := v_parent.depth + 1;
    if new.proceeding_id is null then
      new.proceeding_id := v_parent.proceeding_id;
    elsif new.proceeding_id is distinct from v_parent.proceeding_id then
      raise exception 'nested application must carry the parent proceeding'
        using errcode = '23514';
    end if;
  else
    new.depth := 0;
  end if;
  return new;
end $$;

create or replace function app.freeze_application_parent() returns trigger
language plpgsql as $$
begin
  if old.matter_id is distinct from new.matter_id
     or old.parent_application_id is distinct from new.parent_application_id then
    raise exception 'application matter and parent are immutable'
      using errcode = '55000';
  end if;
  return new;
end $$;

create trigger proceeding_application_parent_guard
  before insert on app.proceeding_application
  for each row execute function app.check_application_parent();
create trigger proceeding_application_parent_freeze
  before update on app.proceeding_application
  for each row execute function app.freeze_application_parent();
create trigger hearing_touch before update on app.hearing
  for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Access functions (defined after the tables they read)
-- ---------------------------------------------------------------------------
create or replace function app.is_member() returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select exists (
    select 1 from app.membership m
    where m.user_id = app.current_user() and m.disabled_at is null
  )
$$;

create or replace function app.is_admin() returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select exists (
    select 1 from app.membership m
    where m.user_id = app.current_user()
      and m.role = 'admin'
      and m.disabled_at is null
  )
$$;

-- One boolean: may this user see this matter? A firm admin sees every Matter.
create or replace function app.has_matter_access(p_matter uuid)
returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select app.is_admin() or exists (
    select 1 from app.matter_member mm
    where mm.matter_id = p_matter
      and mm.revoked_at is null
      and mm.user_id = app.current_user()
  )
$$;

-- A grant on one restricted document; it never widens beyond the Matter.
create or replace function app.has_resource_grant(
  p_type text, p_id uuid, p_level text default 'view'
) returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select exists (
    select 1 from app.resource_grant g
    where g.resource_type = p_type
      and g.resource_id = p_id
      and g.subject_user_id = app.current_user()
      and g.revoked_at is null
      and case g.level
            when 'view' then 1 when 'comment' then 2
            when 'edit' then 3 else 0 end
          >= case p_level
            when 'view' then 1 when 'comment' then 2
            when 'edit' then 3 else 0 end
  )
$$;

create or replace function app.has_document_access(p_document uuid)
returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select exists (
    select 1 from app.document d
    where d.id = p_document
      and app.has_matter_access(d.matter_id)
      and (
        app.is_admin()
        or d.confidentiality = 'matter'
        or app.has_resource_grant('document', d.id, 'view')
      )
  )
$$;

create or replace function app.has_document_version_access(p_version uuid)
returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select exists (
    select 1 from app.document_version dv
    where dv.id = p_version
      and app.has_document_access(dv.document_id)
  )
$$;

create or replace function app.has_document_relation_access(
  p_from_document uuid, p_to_document uuid
) returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select app.has_document_access(p_from_document)
     and app.has_document_access(p_to_document)
$$;

revoke all on function app.current_user() from public;
revoke all on function app.is_member() from public;
revoke all on function app.is_admin() from public;
revoke all on function app.has_matter_access(uuid) from public;
revoke all on function app.has_resource_grant(text,uuid,text) from public;
revoke all on function app.has_document_access(uuid) from public;
revoke all on function app.has_document_version_access(uuid) from public;
revoke all on function app.has_document_relation_access(uuid,uuid) from public;
grant execute on function app.current_user() to maverick_app, maverick_readonly;
grant execute on function app.is_member() to maverick_app, maverick_readonly;
grant execute on function app.is_admin() to maverick_app, maverick_readonly;
grant execute on function app.has_matter_access(uuid) to maverick_app, maverick_readonly;
grant execute on function app.has_resource_grant(text,uuid,text) to maverick_app, maverick_readonly;
grant execute on function app.has_document_access(uuid) to maverick_app, maverick_readonly;
grant execute on function app.has_document_version_access(uuid) to maverick_app, maverick_readonly;
grant execute on function app.has_document_relation_access(uuid,uuid) to maverick_app, maverick_readonly;

alter function app.current_user() owner to maverick_owner;
alter function app.is_member() owner to maverick_owner;
alter function app.is_admin() owner to maverick_owner;
alter function app.has_matter_access(uuid) owner to maverick_owner;
alter function app.has_resource_grant(text,uuid,text) owner to maverick_owner;
alter function app.has_document_access(uuid) owner to maverick_owner;
alter function app.has_document_version_access(uuid) owner to maverick_owner;
alter function app.has_document_relation_access(uuid,uuid) owner to maverick_owner;

-- ---------------------------------------------------------------------------
-- RLS: every table with matter_id gets the same policy
-- ---------------------------------------------------------------------------
do $$
declare t record;
begin
  for t in
    select c.table_name
    from information_schema.columns c
    where c.table_schema = 'app' and c.column_name = 'matter_id'
      and c.table_name not in ('matter_member')
  loop
    execute format('alter table app.%I enable row level security', t.table_name);
    execute format('alter table app.%I force row level security', t.table_name);
    execute format('drop policy if exists %I on app.%I', t.table_name || '_matter', t.table_name);
    execute format(
      'create policy %I on app.%I for all using (app.has_matter_access(matter_id)) with check (app.has_matter_access(matter_id))',
      t.table_name || '_matter', t.table_name);
  end loop;
end $$;

-- Resource-level policies replace the generic matter policy where a row can be
-- narrower than the Matter.
drop policy if exists document_matter on app.document;
create policy document_access on app.document for all
  using (app.has_document_access(id))
  with check (app.has_matter_access(matter_id)
              and (app.is_admin()
                   or confidentiality = 'matter'
                   or app.has_resource_grant('document', id, 'edit')));
-- The access function reads this table as the migration owner. The app role is
-- still subject to the policy. NO FORCE prevents recursion through the function.
alter table app.document no force row level security;

drop policy if exists document_version_matter on app.document_version;
create policy document_version_access on app.document_version for all
  using (app.has_document_access(document_id))
  with check (app.has_document_access(document_id));

drop policy if exists document_text_matter on app.document_text;
create policy document_text_access on app.document_text for all
  using (app.has_document_version_access(document_version_id))
  with check (app.has_document_version_access(document_version_id));

drop policy if exists document_anchor_matter on app.document_anchor;
create policy document_anchor_access on app.document_anchor for all
  using (app.has_document_version_access(document_version_id))
  with check (app.has_document_version_access(document_version_id));

drop policy if exists annotation_matter on app.annotation;
create policy annotation_access on app.annotation for all
  using (app.has_document_version_access(document_version_id))
  with check (app.has_document_version_access(document_version_id));

drop policy if exists document_chunk_matter on app.document_chunk;
create policy document_chunk_access on app.document_chunk for all
  using (app.has_document_version_access(document_version_id))
  with check (app.has_document_version_access(document_version_id));

drop policy if exists document_relation_matter on app.document_relation;
create policy document_relation_access on app.document_relation for all
  using (app.has_document_relation_access(from_document_id, to_document_id))
  with check (app.has_matter_access(matter_id)
              and app.has_document_access(from_document_id)
              and app.has_document_access(to_document_id));

drop policy if exists editing_session_matter on app.editing_session;
create policy editing_session_access on app.editing_session for all
  using (app.has_document_access(document_id))
  with check (app.has_document_access(document_id));

drop policy if exists document_proposal_matter on app.document_proposal;
create policy document_proposal_access on app.document_proposal for all
  using (app.has_document_access(document_id))
  with check (app.has_document_access(document_id));

drop policy if exists notification_matter on app.notification;
create policy notification_recipient on app.notification for all
  using (recipient_user_id = app.current_user() or app.is_admin())
  with check (recipient_user_id = app.current_user() or app.is_admin());

drop policy if exists resource_grant_matter on app.resource_grant;
create policy resource_grant_read on app.resource_grant for select using (
  app.is_admin()
  or subject_user_id = app.current_user()
  or exists (select 1 from app.matter m
             where m.id = matter_id and m.responsible_user_id = app.current_user()));
create policy resource_grant_write on app.resource_grant for all using (
  app.is_admin()
  or exists (select 1 from app.matter m
             where m.id = matter_id and m.responsible_user_id = app.current_user()))
  with check (
  app.is_admin()
  or exists (select 1 from app.matter m
             where m.id = matter_id and m.responsible_user_id = app.current_user()));

drop policy if exists job_matter on app.job;
create policy job_access on app.job for all
  using (case when matter_id is null then app.is_admin()
              else app.has_matter_access(matter_id) end)
  with check (case when matter_id is null then app.is_admin()
                   else app.has_matter_access(matter_id) end);

-- blobs have no matter_id; they are readable only through a document version
-- or a template the user can already see. The storage service inserts bytes
-- before the referencing row exists, so insert is open to the app role.
alter table app.blob enable row level security;
create policy blob_read on app.blob
  for select using (
    exists (select 1 from app.document_version dv where dv.blob_sha256 = app.blob.sha256)
    or exists (select 1 from app.template t where t.blob_sha256 = app.blob.sha256)
    or exists (select 1 from app.rule_snapshot rs where rs.blob_sha256 = app.blob.sha256)
  );
create policy blob_insert on app.blob
  for insert with check (true);

-- matter has id, not matter_id
alter table app.matter enable row level security;
alter table app.matter force row level security;
create policy matter_access on app.matter
  for all using (app.has_matter_access(id)) with check (app.has_matter_access(id));

-- a relation is visible only if the user can see the source matter.
alter table app.matter_relation enable row level security;
create policy matter_relation_access on app.matter_relation
  for all using (app.has_matter_access(from_matter_id))
  with check (app.has_matter_access(from_matter_id));

-- cross-matter reuse: readable by either side; writable only when both sides
-- are visible. A relation alone never grants access.
alter table app.reuse_grant enable row level security;
create policy reuse_grant_read on app.reuse_grant
  for select using (app.has_matter_access(source_matter_id) or app.has_matter_access(target_matter_id));
create policy reuse_grant_write on app.reuse_grant
  for all using (app.has_matter_access(source_matter_id) and app.has_matter_access(target_matter_id))
  with check (app.has_matter_access(source_matter_id) and app.has_matter_access(target_matter_id));

-- membership tables: a user sees their own row; admins see all.
alter table app.membership enable row level security;
create policy membership_self on app.membership
  for select using (user_id = app.current_user() or app.is_admin());
create policy membership_admin on app.membership
  for all using (app.is_admin()) with check (app.is_admin());

-- matter grants: a user sees their own grant; an admin manages every grant.
alter table app.matter_member enable row level security;
create policy matter_member_self on app.matter_member
  for select using (user_id = app.current_user());
create policy matter_member_admin on app.matter_member
  for all using (app.is_admin()) with check (app.is_admin());

-- firm-wide reference and people data
do $$
declare t text;
begin
  foreach t in array array['contact','client','forum',
                           'source','authority','authority_version','template',
                           'bundle','bundle_version','skill',
                           'playbook','rule_instrument','format_rule','rule_snapshot','egress_policy',
                           'legal_instrument','instrument_version','instrument_snapshot','provision',
                           'judgment','judgment_version','judgment_snapshot',
                           'workflow_definition','workflow_version']
  loop
    execute format('alter table app.%I enable row level security', t);
    execute format('drop policy if exists %I on app.%I', t || '_firm', t);
    execute format('create policy %I on app.%I for all using (app.is_member()) with check (app.is_member())', t || '_firm', t);
  end loop;
end $$;

-- forum adapters: members read; admin writes
alter table app.forum_adapter enable row level security;
create policy forum_adapter_read on app.forum_adapter for select using (app.is_member());
create policy forum_adapter_write on app.forum_adapter for all using (app.is_admin()) with check (app.is_admin());

-- library: admin publishes; a member reads only with a grant
alter table app.library_item enable row level security;
create policy library_item_read on app.library_item for select using (
  app.is_admin() or (
    status = 'published' and exists (
      select 1 from app.library_grant g
      where g.item_id = library_item.id
        and (g.subject_user_id = app.current_user()
             or (g.subject_role is not null and exists (
               select 1 from app.membership m
               where m.user_id = app.current_user() and m.role = g.subject_role)))
    )));
create policy library_item_admin on app.library_item for all using (app.is_admin()) with check (app.is_admin());

alter table app.library_version enable row level security;
create policy library_version_read on app.library_version for select using (app.is_admin() or exists (
  select 1 from app.library_item i
  where i.id = library_version.item_id and i.status = 'published'
    and exists (
      select 1 from app.library_grant g
      where g.item_id = i.id
        and (g.subject_user_id = app.current_user()
             or (g.subject_role is not null and exists (
               select 1 from app.membership m
               where m.user_id = app.current_user() and m.role = g.subject_role)))
    )));
create policy library_version_admin on app.library_version for all using (app.is_admin()) with check (app.is_admin());

alter table app.library_grant enable row level security;
create policy library_grant_read on app.library_grant for select using (
  app.is_admin() or subject_user_id = app.current_user()
  or (subject_role is not null and exists (
    select 1 from app.membership m
    where m.user_id = app.current_user() and m.role = subject_role)));
create policy library_grant_admin on app.library_grant for all using (app.is_admin()) with check (app.is_admin());

-- execution nodes: self or admin
alter table app.execution_node enable row level security;
create policy execution_node_self on app.execution_node for all
  using (user_id = app.current_user() or app.is_admin())
  with check (user_id = app.current_user() or app.is_admin());

-- user: self or admin
alter table app.user enable row level security;
create policy user_self on app.user
  for select using (id = app.current_user() or app.is_admin());
create policy user_admin on app.user
  for all using (app.is_admin()) with check (app.is_admin());

-- firm: all members read; owner writes
alter table app.firm enable row level security;
create policy firm_read on app.firm for select using (app.is_member());
create policy firm_write on app.firm for all using (app.is_admin()) with check (app.is_admin());

-- session and device: self or admin
alter table app.session enable row level security;
create policy session_self on app.session for all using (user_id = app.current_user() or app.is_admin());
alter table app.device enable row level security;
create policy device_self on app.device for all using (user_id = app.current_user() or app.is_admin());

-- audit: read with matter access; append only through the function
alter table audit.audit_event enable row level security;
create policy audit_read on audit.audit_event
  for select using (
    (matter_id is null and app.is_admin())
    or (matter_id is not null and app.has_matter_access(matter_id))
  );

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
grant select, insert, update, delete on all tables in schema app to maverick_app;
grant select on all tables in schema app to maverick_readonly;
grant select on ref.document_type to maverick_app, maverick_readonly;
grant select on audit.audit_event to maverick_app, maverick_readonly;
grant usage, select on all sequences in schema app, audit to maverick_app;
grant execute on all functions in schema app to maverick_app;
grant execute on function audit.append(text,uuid,text,text,uuid,uuid,text,jsonb,text,text,uuid,uuid,text,uuid) to maverick_app;

-- Legal-hold and deletion tables are deliberately absent here; they follow
-- the same matter_id + RLS pattern. See docs/v1/03-application-agent-and-data.md
-- §9 (retention and legal hold) and docs/v1/04-shared-workspaces-and-collaboration.md
-- §4-§5 (deletion and legal hold).

-- ---------------------------------------------------------------------------
-- Table ownership manifest (one writer per table)
-- ---------------------------------------------------------------------------
create table if not exists ops.table_owner (
  table_name text primary key,
  module     text not null,
  notes      text
);

insert into ops.table_owner (table_name, module) values
  ('firm','identity'), ('user','identity'), ('membership','identity'), ('session','identity'), ('device','identity'),
  ('execution_node','identity'),
  ('matter','matter'), ('matter_relation','matter'), ('matter_party','matter'), ('note','matter'),
  ('matter_member','access'), ('reuse_grant','access'), ('resource_grant','access'),
  ('contact','contacts'), ('client','contacts'),
  ('forum','courts'), ('forum_adapter','forum_adapters'),
  ('proceeding','proceedings'), ('proceeding_application','proceedings'), ('hearing','proceedings'),
  ('order','proceedings'), ('registry_event','proceedings'), ('exhibit','proceedings'),
  ('task','work'), ('task_document','work'), ('deadline','work'), ('appointment','work'),
  ('folder','documents'), ('document','documents'), ('document_version','documents'),
  ('document_anchor','documents'), ('document_text','documents'), ('document_relation','documents'),
  ('document_chunk','documents'), ('annotation','documents'), ('editing_session','documents'),
  ('document_proposal','documents'),
  ('template','library'), ('library_item','library'), ('library_version','library'), ('library_grant','library'),
  ('blob','storage'),
  ('classification','classification'),
  ('source','corpus'), ('legal_instrument','corpus'), ('instrument_version','corpus'),
  ('instrument_snapshot','corpus'), ('provision','corpus'),
  ('authority','case_law'), ('authority_version','case_law'), ('judgment','case_law'),
  ('judgment_version','case_law'), ('judgment_snapshot','case_law'),
  ('research_query','research'), ('research_result','research'), ('retrieval_packet','research'),
  ('research_project','research_studio'), ('research_plan','research_studio'),
  ('fact','facts'), ('fact_position','facts'), ('evidence','facts'), ('evidence_status','facts'),
  ('fact_evidence','facts'),
  ('rule_instrument','corpus'), ('format_rule','rules'), ('rule_snapshot','corpus'),
  ('citation','verification'), ('verification_run','verification'),
  ('approval','approvals'), ('decision','approvals'), ('gate','approvals'),
  ('filing','filing'), ('filing_item','filing'),
  ('bundle','capabilities'), ('bundle_version','capabilities'), ('skill','capabilities'),
  ('playbook','workflow'), ('playbook_run','workflow'), ('step_run','workflow'),
  ('workflow_definition','workflow'), ('workflow_version','workflow'),
  ('workflow_run','workflow'), ('workflow_step','workflow'), ('job','workflow'),
  ('conversation','harness'), ('message','harness'), ('agent_run','harness'), ('agent_event','harness'),
  ('context_package','harness'), ('run_bundle','harness'),
  ('browser_session','browser'), ('browser_control_lease','browser'),
  ('notification','notifications'), ('notification_delivery','notifications'),
  ('egress_policy','policy'),
  ('audit_event','audit')
on conflict (table_name) do nothing;

-- ---------------------------------------------------------------------------
-- CRM schema amendments
-- The baseline is mutable pre-pilot. These changes are part of the baseline;
-- update the digest in migrations/baseline.py and the RLS probes with them.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Identity: credentials and delegation
-- ---------------------------------------------------------------------------
create table app.user_credential (
  user_id       uuid primary key references app.user(id) on delete cascade,
  password_hash text,
  totp_secret   text,
  updated_at    timestamptz not null default now()
);

alter table app.user drop column if exists password_hash;
alter table app.user drop column if exists totp_secret;

alter table app.user_credential enable row level security;
revoke all on app.user_credential from maverick_app, maverick_readonly;
grant select, insert, update, delete on app.user_credential to maverick_owner;

create table app.delegation (
  id                uuid primary key default gen_random_uuid(),
  firm_id           uuid not null references app.firm(id) on delete cascade,
  delegator_user_id uuid not null references app.user(id) on delete cascade,
  delegate_user_id  uuid not null references app.user(id) on delete cascade,
  scope             text not null check (scope in ('all','access','review','library','settings')),
  starts_at         timestamptz not null default now(),
  ends_at           timestamptz,
  revoked_at        timestamptz,
  created_at        timestamptz not null default now(),
  check (delegator_user_id <> delegate_user_id),
  check (ends_at is null or ends_at > starts_at)
);
create unique index delegation_live
  on app.delegation (firm_id, delegator_user_id, delegate_user_id, scope)
  where revoked_at is null;

alter table app.delegation enable row level security;
alter table app.delegation force row level security;
create policy delegation_admin on app.delegation for all
  using (app.is_admin()) with check (app.is_admin());
create policy delegation_read on app.delegation for select
  using (delegator_user_id = app.current_user() or delegate_user_id = app.current_user());

create table app.matter_close (
  id          uuid primary key default gen_random_uuid(),
  matter_id   uuid not null unique references app.matter(id) on delete cascade,
  closed_by   uuid not null references app.user(id),
  closed_at   timestamptz not null default now(),
  reopened_at timestamptz,
  disposition jsonb not null default '{}'::jsonb,
  note        text
);

-- ---------------------------------------------------------------------------
-- Citations and case-law identity
-- ---------------------------------------------------------------------------
alter table app.judgment add column if not exists neutral_citation text;
create unique index if not exists judgment_neutral_citation
  on app.judgment (neutral_citation) where neutral_citation is not null;

alter table app.citation
  alter column authority_id drop not null,
  add column if not exists judgment_version_id uuid references app.judgment_version(id),
  add column if not exists instrument_version_id uuid references app.instrument_version(id),
  add column if not exists provision_id uuid references app.provision(id),
  add column if not exists cited_document_version_id uuid references app.document_version(id),
  add column if not exists source_id uuid references app.source(id),
  add column if not exists target_kind text generated always as (
    case
      when judgment_version_id is not null then 'case_law'
      when provision_id is not null then 'provision'
      when instrument_version_id is not null then 'instrument'
      when cited_document_version_id is not null then 'source_material'
      when source_id is not null then 'external'
      when authority_id is not null then 'legacy_authority'
      else 'none'
    end
  ) stored;

alter table app.citation
  add constraint citation_one_target check (
    num_nonnulls(
      authority_id,
      judgment_version_id,
      instrument_version_id,
      provision_id,
      cited_document_version_id,
      source_id
    ) = 1
  );
alter table app.citation
  add constraint citation_authority_version check (
    authority_version_id is null or authority_id is not null
  );

-- ---------------------------------------------------------------------------
-- Firm-level approvals and gates
-- ---------------------------------------------------------------------------
alter table app.approval
  alter column matter_id drop not null,
  add column if not exists firm_id uuid references app.firm(id);
alter table app.approval
  add constraint approval_scope check (matter_id is not null or firm_id is not null);

alter table app.gate
  alter column matter_id drop not null,
  add column if not exists firm_id uuid references app.firm(id);
alter table app.gate
  add constraint gate_scope check (matter_id is not null or firm_id is not null);

alter table app."order"
  add constraint order_document_fk foreign key (document_id) references app.document(id);
alter table app.approval
  add constraint approval_requested_run_fk foreign key (requested_run_id) references app.agent_run(id);
alter table app.document_version
  add constraint document_version_created_run_fk foreign key (created_run_id) references app.agent_run(id);

-- ---------------------------------------------------------------------------
-- Grant and reference uniqueness
-- ---------------------------------------------------------------------------
do $$
declare c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'app.resource_grant'::regclass and contype = 'u'
  loop
    execute format('alter table app.resource_grant drop constraint %I', c.conname);
  end loop;
end $$;
create unique index if not exists resource_grant_live
  on app.resource_grant (resource_type, resource_id, subject_user_id)
  where revoked_at is null;

alter table app.library_grant add column if not exists revoked_at timestamptz;
create unique index if not exists library_grant_live
  on app.library_grant (
    item_id,
    coalesce(subject_user_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(subject_role, '')
  )
  where revoked_at is null;

create unique index if not exists forum_root_name
  on app.forum (coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), name);

-- ---------------------------------------------------------------------------
-- Access helpers
-- ---------------------------------------------------------------------------
create or replace function app.is_member() returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select exists (
    select 1 from app.membership m
    join app.user u on u.id = m.user_id
    where m.user_id = app.current_user()
      and m.disabled_at is null
      and u.status = 'active'
  )
$$;

create or replace function app.is_admin() returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select exists (
    select 1 from app.membership m
    join app.user u on u.id = m.user_id
    where m.user_id = app.current_user()
      and m.role = 'admin'
      and m.disabled_at is null
      and u.status = 'active'
  )
$$;

create or replace function app.has_matter_access(p_matter uuid, p_level text)
returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select app.is_admin() or exists (
    select 1 from app.matter_member mm
    where mm.matter_id = p_matter
      and mm.revoked_at is null
      and mm.user_id = app.current_user()
      and (p_level = 'view' or mm.access = 'edit')
  )
$$;

create or replace function app.has_matter_access(p_matter uuid)
returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select app.has_matter_access(p_matter, 'view')
$$;

create or replace function app.has_document_access(p_document uuid, p_level text)
returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select exists (
    select 1 from app.document d
    where d.id = p_document
      and app.has_matter_access(d.matter_id, p_level)
      and (
        app.is_admin()
        or d.confidentiality = 'matter'
        or app.has_resource_grant('document', d.id, case when p_level = 'edit' then 'edit' else 'view' end)
      )
  )
$$;

create or replace function app.has_document_access(p_document uuid)
returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select app.has_document_access(p_document, 'view')
$$;

create or replace function app.has_document_version_access(p_version uuid, p_level text)
returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select exists (
    select 1 from app.document_version dv
    where dv.id = p_version
      and app.has_document_access(dv.document_id, p_level)
  )
$$;

create or replace function app.has_document_version_access(p_version uuid)
returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select app.has_document_version_access(p_version, 'view')
$$;

create or replace function app.is_delegate(p_scope text)
returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select exists (
    select 1 from app.delegation d
    where d.delegate_user_id = app.current_user()
      and d.revoked_at is null
      and (d.ends_at is null or d.ends_at > now())
      and (d.scope = 'all' or d.scope = p_scope)
  )
$$;

create or replace function app.can_administer_matter(p_matter uuid)
returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select app.is_admin()
     or (app.is_delegate('access') and app.has_matter_access(p_matter, 'edit'))
     or exists (
       select 1 from app.matter m
       where m.id = p_matter and m.responsible_user_id = app.current_user()
     )
$$;

create or replace function app.can_approve(p_matter uuid)
returns boolean
language sql stable security definer
set search_path = app, pg_temp as $$
  select app.has_matter_access(p_matter, 'edit')
     and (
       app.is_admin()
       or exists (
         select 1 from app.membership m
         where m.user_id = app.current_user()
           and m.role = 'lawyer'
           and m.disabled_at is null
       )
     )
$$;

create or replace function app.bump_revision() returns trigger
language plpgsql as $$
begin
  new.revision := coalesce(old.revision, 0) + 1;
  return new;
end $$;

revoke all on function app.is_member() from public;
revoke all on function app.is_admin() from public;
revoke all on function app.has_matter_access(uuid) from public;
revoke all on function app.has_matter_access(uuid, text) from public;
revoke all on function app.has_document_access(uuid) from public;
revoke all on function app.has_document_access(uuid, text) from public;
revoke all on function app.has_document_version_access(uuid) from public;
revoke all on function app.has_document_version_access(uuid, text) from public;
revoke all on function app.is_delegate(text) from public;
revoke all on function app.can_administer_matter(uuid) from public;
revoke all on function app.can_approve(uuid) from public;
grant execute on function app.is_member() to maverick_app, maverick_readonly;
grant execute on function app.is_admin() to maverick_app, maverick_readonly;
grant execute on function app.has_matter_access(uuid) to maverick_app, maverick_readonly;
grant execute on function app.has_matter_access(uuid, text) to maverick_app, maverick_readonly;
grant execute on function app.has_document_access(uuid) to maverick_app, maverick_readonly;
grant execute on function app.has_document_access(uuid, text) to maverick_app, maverick_readonly;
grant execute on function app.has_document_version_access(uuid) to maverick_app, maverick_readonly;
grant execute on function app.has_document_version_access(uuid, text) to maverick_app, maverick_readonly;
grant execute on function app.is_delegate(text) to maverick_app, maverick_readonly;
grant execute on function app.can_administer_matter(uuid) to maverick_app, maverick_readonly;
grant execute on function app.can_approve(uuid) to maverick_app, maverick_readonly;

alter function app.is_member() owner to maverick_owner;
alter function app.is_admin() owner to maverick_owner;
alter function app.has_matter_access(uuid) owner to maverick_owner;
alter function app.has_matter_access(uuid, text) owner to maverick_owner;
alter function app.has_document_access(uuid) owner to maverick_owner;
alter function app.has_document_access(uuid, text) owner to maverick_owner;
alter function app.has_document_version_access(uuid) owner to maverick_owner;
alter function app.has_document_version_access(uuid, text) owner to maverick_owner;
alter function app.is_delegate(text) owner to maverick_owner;
alter function app.can_administer_matter(uuid) owner to maverick_owner;
alter function app.can_approve(uuid) owner to maverick_owner;
alter function app.bump_revision() owner to maverick_owner;

alter table app.matter_close enable row level security;
alter table app.matter_close force row level security;
create policy matter_close_read on app.matter_close for select
  using (app.has_matter_access(matter_id, 'view'));
create policy matter_close_write on app.matter_close for all
  using (app.can_administer_matter(matter_id))
  with check (app.can_administer_matter(matter_id));

-- ---------------------------------------------------------------------------
-- Level-aware Matter RLS
-- ---------------------------------------------------------------------------
do $$
declare t record;
begin
  for t in
    select c.table_name
    from information_schema.columns c
    where c.table_schema = 'app'
      and c.column_name = 'matter_id'
      and c.table_name <> 'matter_member'
  loop
    execute format('alter table app.%I enable row level security', t.table_name);
    execute format('alter table app.%I force row level security', t.table_name);
    execute format('drop policy if exists %I on app.%I', t.table_name || '_matter', t.table_name);
    execute format('drop policy if exists %I on app.%I', t.table_name || '_read', t.table_name);
    execute format('drop policy if exists %I on app.%I', t.table_name || '_write', t.table_name);
    execute format(
      'create policy %I on app.%I for select using (app.has_matter_access(matter_id, ''view''))',
      t.table_name || '_read', t.table_name);
    execute format(
      'create policy %I on app.%I for all using (app.has_matter_access(matter_id, ''edit'')) with check (app.has_matter_access(matter_id, ''edit''))',
      t.table_name || '_write', t.table_name);
  end loop;
end $$;

-- matter: read by members, update by editors, insert/delete by admin
drop policy if exists matter_access on app.matter;
drop policy if exists matter_read on app.matter;
drop policy if exists matter_update on app.matter;
drop policy if exists matter_insert on app.matter;
drop policy if exists matter_delete on app.matter;
create policy matter_read on app.matter for select
  using (app.has_matter_access(id, 'view'));
create policy matter_update on app.matter for update
  using (app.has_matter_access(id, 'edit'))
  with check (app.has_matter_access(id, 'edit'));
create policy matter_insert on app.matter for insert
  with check (app.is_admin());
create policy matter_delete on app.matter for delete
  using (false);

-- matter_member: read by members, write by admin/delegate/responsible lawyer
drop policy if exists matter_member_self on app.matter_member;
drop policy if exists matter_member_admin on app.matter_member;
drop policy if exists matter_member_read on app.matter_member;
drop policy if exists matter_member_write on app.matter_member;
create policy matter_member_read on app.matter_member for select
  using (app.has_matter_access(matter_id, 'view'));
create policy matter_member_write on app.matter_member for all
  using (app.can_administer_matter(matter_id))
  with check (app.can_administer_matter(matter_id));

-- resource grants: read by subject/admin/responsible lawyer; write by same
drop policy if exists resource_grant_matter on app.resource_grant;
drop policy if exists resource_grant_read on app.resource_grant;
drop policy if exists resource_grant_write on app.resource_grant;
create policy resource_grant_read on app.resource_grant for select
  using (
    app.is_admin()
    or subject_user_id = app.current_user()
    or app.can_administer_matter(matter_id)
  );
create policy resource_grant_write on app.resource_grant for all
  using (app.can_administer_matter(matter_id))
  with check (app.can_administer_matter(matter_id));

-- document: read follows the document grant; write requires Matter edit
drop policy if exists document_matter on app.document;
drop policy if exists document_access on app.document;
drop policy if exists document_read on app.document;
drop policy if exists document_update on app.document;
drop policy if exists document_insert on app.document;
drop policy if exists document_delete on app.document;
create policy document_read on app.document for select
  using (app.has_document_access(id, 'view'));
create policy document_update on app.document for update
  using (app.has_document_access(id, 'edit'))
  with check (app.has_document_access(id, 'edit'));
create policy document_insert on app.document for insert
  with check (
    app.has_matter_access(matter_id, 'edit')
    and (confidentiality = 'matter' or app.is_admin() or created_by = app.current_user())
  );
create policy document_delete on app.document for delete
  using (false);
alter table app.document no force row level security;

-- document_version: read follows the document; editor_save requires the lease
drop policy if exists document_version_matter on app.document_version;
drop policy if exists document_version_access on app.document_version;
drop policy if exists document_version_read on app.document_version;
drop policy if exists document_version_insert on app.document_version;
create policy document_version_read on app.document_version for select
  using (app.has_document_access(document_id, 'view'));
create policy document_version_insert on app.document_version for insert
  with check (
    app.has_document_access(document_id, 'edit')
    and (
      source <> 'editor_save'
      or exists (
        select 1 from app.editing_session s
        where s.document_id = document_id
          and s.opened_by = app.current_user()
          and s.status in ('opening','active')
      )
    )
  );

-- editing session: read by document readers; write by document editors
drop policy if exists editing_session_matter on app.editing_session;
drop policy if exists editing_session_access on app.editing_session;
drop policy if exists editing_session_read on app.editing_session;
drop policy if exists editing_session_write on app.editing_session;
create policy editing_session_read on app.editing_session for select
  using (app.has_document_access(document_id, 'view'));
create policy editing_session_write on app.editing_session for all
  using (app.has_document_access(document_id, 'edit'))
  with check (app.has_document_access(document_id, 'edit'));

-- document proposals: read by document readers; write by document editors
drop policy if exists document_proposal_matter on app.document_proposal;
drop policy if exists document_proposal_access on app.document_proposal;
drop policy if exists document_proposal_read on app.document_proposal;
drop policy if exists document_proposal_write on app.document_proposal;
create policy document_proposal_read on app.document_proposal for select
  using (app.has_document_access(document_id, 'view'));
create policy document_proposal_write on app.document_proposal for all
  using (app.has_document_access(document_id, 'edit'))
  with check (app.has_document_access(document_id, 'edit'));

-- approvals and gates: write only by an eligible approver
drop policy if exists approval_matter on app.approval;
drop policy if exists approval_read on app.approval;
drop policy if exists approval_write on app.approval;
create policy approval_read on app.approval for select
  using (
    case when matter_id is null then app.is_admin()
         else app.has_matter_access(matter_id, 'view') end
  );
create policy approval_write on app.approval for all
  using (
    case when matter_id is null then app.is_admin()
         else app.can_approve(matter_id) end
  )
  with check (
    case when matter_id is null then app.is_admin()
         else app.can_approve(matter_id) end
  );

drop policy if exists gate_matter on app.gate;
drop policy if exists gate_read on app.gate;
drop policy if exists gate_write on app.gate;
create policy gate_read on app.gate for select
  using (
    case when matter_id is null then app.is_admin()
         else app.has_matter_access(matter_id, 'view') end
  );
create policy gate_write on app.gate for all
  using (
    case when matter_id is null then app.is_admin()
         else app.can_approve(matter_id) end
  )
  with check (
    case when matter_id is null then app.is_admin()
         else app.can_approve(matter_id) end
  );

-- notification delivery: a recipient can read their own delivery
drop policy if exists notification_delivery_matter on app.notification_delivery;
drop policy if exists notification_delivery_read on app.notification_delivery;
create policy notification_delivery_read on app.notification_delivery for select
  using (
    (matter_id is null and exists (
      select 1 from app.notification n
      where n.id = notification_id
        and n.recipient_user_id = app.current_user()
    ))
    or (matter_id is not null and app.has_matter_access(matter_id, 'view'))
  );

-- blobs: include every live blob-bearing table
drop policy if exists blob_read on app.blob;
create policy blob_read on app.blob for select using (
  exists (select 1 from app.document_version dv where dv.blob_sha256 = app.blob.sha256)
  or exists (select 1 from app.template t where t.blob_sha256 = app.blob.sha256)
  or exists (select 1 from app.rule_snapshot rs where rs.blob_sha256 = app.blob.sha256)
  or exists (select 1 from app.instrument_snapshot s where s.blob_sha256 = app.blob.sha256)
  or exists (select 1 from app.judgment_snapshot s where s.blob_sha256 = app.blob.sha256)
  or exists (select 1 from app.library_version lv where lv.blob_sha256 = app.blob.sha256)
  or exists (select 1 from app.retrieval_packet rp where rp.blob_sha256 = app.blob.sha256)
);

-- library grants: admin or delegated librarian writes
drop policy if exists library_grant_admin on app.library_grant;
drop policy if exists library_grant_write on app.library_grant;
create policy library_grant_write on app.library_grant for all
  using (app.is_admin() or app.is_delegate('library'))
  with check (app.is_admin() or app.is_delegate('library'));

-- ---------------------------------------------------------------------------
-- Revision tokens
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'matter','folder','document','note','task','deadline','appointment',
    'conversation','classification','research_project','research_plan',
    'workflow_run','workflow_step','document_proposal','editing_session',
    'approval','gate','decision','filing','proceeding','hearing','order',
    'resource_grant','library_item','library_version','matter_close'
  ]
  loop
    execute format('alter table app.%I add column if not exists revision bigint not null default 1', t);
    execute format('drop trigger if exists %I on app.%I', t || '_revision', t);
    execute format(
      'create trigger %I before update on app.%I for each row execute function app.bump_revision()',
      t || '_revision', t);
  end loop;
end $$;

-- Remaining mutable Matter resources: add a revision where it is meaningful.
do $$
declare t text;
begin
  for t in
    select c.table_name
    from information_schema.columns c
    where c.table_schema = 'app'
      and c.column_name = 'matter_id'
      and c.table_name not in (
        'document_version','document_text','document_chunk','document_anchor',
        'agent_event','agent_run','context_package','message',
        'fact_position','evidence_status','registry_event','run_bundle',
        'playbook_run','step_run','job','notification_delivery',
        'verification_run','retrieval_packet'
      )
      and not exists (
        select 1 from information_schema.columns r
        where r.table_schema = 'app'
          and r.table_name = c.table_name
          and r.column_name = 'revision'
      )
  loop
    execute format('alter table app.%I add column revision bigint not null default 1', t);
    execute format(
      'create trigger %I before update on app.%I for each row execute function app.bump_revision()',
      t || '_revision', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Same-Matter guards
-- ---------------------------------------------------------------------------
create or replace function app.check_document_scope() returns trigger
language plpgsql as $$
declare v_matter uuid;
begin
  if new.folder_id is not null then
    select matter_id into v_matter from app.folder where id = new.folder_id;
    if v_matter is distinct from new.matter_id then
      raise exception 'document folder belongs to another matter' using errcode = '23514';
    end if;
  end if;
  if new.current_version_id is not null then
    select matter_id into v_matter from app.document_version where id = new.current_version_id;
    if v_matter is distinct from new.matter_id then
      raise exception 'document current version belongs to another matter' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
create trigger document_scope before insert or update on app.document
  for each row execute function app.check_document_scope();

create or replace function app.check_filing_item_scope() returns trigger
language plpgsql as $$
declare v_document uuid; v_matter uuid;
begin
  select document_id, matter_id into v_document, v_matter
    from app.document_version where id = new.document_version_id;
  if v_document is distinct from new.document_id or v_matter is distinct from new.matter_id then
    raise exception 'filing item version belongs to another document or matter' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger filing_item_scope before insert or update on app.filing_item
  for each row execute function app.check_filing_item_scope();

create or replace function app.check_exhibit_scope() returns trigger
language plpgsql as $$
declare v_matter uuid;
begin
  select matter_id into v_matter from app.evidence where id = new.evidence_id;
  if v_matter is distinct from new.matter_id then
    raise exception 'exhibit evidence belongs to another matter' using errcode = '23514';
  end if;
  select matter_id into v_matter from app.proceeding where id = new.proceeding_id;
  if v_matter is distinct from new.matter_id then
    raise exception 'exhibit proceeding belongs to another matter' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger exhibit_scope before insert or update on app.exhibit
  for each row execute function app.check_exhibit_scope();

create or replace function app.check_fact_evidence_scope() returns trigger
language plpgsql as $$
declare v_matter uuid;
begin
  select matter_id into v_matter from app.fact where id = new.fact_id;
  if v_matter is distinct from new.matter_id then
    raise exception 'fact belongs to another matter' using errcode = '23514';
  end if;
  select matter_id into v_matter from app.evidence where id = new.evidence_id;
  if v_matter is distinct from new.matter_id then
    raise exception 'evidence belongs to another matter' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger fact_evidence_scope before insert or update on app.fact_evidence
  for each row execute function app.check_fact_evidence_scope();

create or replace function app.check_task_document_scope() returns trigger
language plpgsql as $$
declare v_matter uuid;
begin
  select matter_id into v_matter from app.task where id = new.task_id;
  if v_matter is distinct from new.matter_id then
    raise exception 'task belongs to another matter' using errcode = '23514';
  end if;
  select matter_id into v_matter from app.document where id = new.document_id;
  if v_matter is distinct from new.matter_id then
    raise exception 'document belongs to another matter' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger task_document_scope before insert or update on app.task_document
  for each row execute function app.check_task_document_scope();

create or replace function app.check_document_relation_scope() returns trigger
language plpgsql as $$
declare v_matter uuid;
begin
  select matter_id into v_matter from app.document where id = new.from_document_id;
  if v_matter is distinct from new.matter_id then
    raise exception 'relation source belongs to another matter' using errcode = '23514';
  end if;
  select matter_id into v_matter from app.document where id = new.to_document_id;
  if v_matter is distinct from new.matter_id then
    raise exception 'relation target belongs to another matter' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger document_relation_scope before insert or update on app.document_relation
  for each row execute function app.check_document_relation_scope();

create or replace function app.check_document_proposal_scope() returns trigger
language plpgsql as $$
declare v_document uuid;
begin
  select document_id into v_document from app.document_version where id = new.base_version_id;
  if v_document is distinct from new.document_id then
    raise exception 'proposal base belongs to another document' using errcode = '23514';
  end if;
  if new.applied_version_id is not null then
    select document_id into v_document from app.document_version where id = new.applied_version_id;
    if v_document is distinct from new.document_id then
      raise exception 'proposal result belongs to another document' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
create trigger document_proposal_scope before insert or update on app.document_proposal
  for each row execute function app.check_document_proposal_scope();

create or replace function app.check_message_run_scope() returns trigger
language plpgsql as $$
declare v_matter uuid;
begin
  if new.author_run_id is not null then
    select matter_id into v_matter from app.agent_run where id = new.author_run_id;
    if v_matter is distinct from new.matter_id then
      raise exception 'message run belongs to another matter' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
create trigger message_run_scope before insert or update on app.message
  for each row execute function app.check_message_run_scope();

create or replace function app.check_browser_lease_scope() returns trigger
language plpgsql as $$
declare v_matter uuid;
begin
  select matter_id into v_matter from app.browser_session where id = new.session_id;
  if v_matter is distinct from new.matter_id then
    raise exception 'browser session belongs to another matter' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger browser_lease_scope before insert or update on app.browser_control_lease
  for each row execute function app.check_browser_lease_scope();

-- ---------------------------------------------------------------------------
-- Delete and append-only guards
-- ---------------------------------------------------------------------------
create or replace function app.reject_delete() returns trigger
language plpgsql as $$
begin
  raise exception 'delete is disabled; archive instead' using errcode = '55000';
end $$;

create or replace function app.reject_nonempty_delete() returns trigger
language plpgsql as $$
begin
  if exists (select 1 from app.document where folder_id = old.id) then
    raise exception 'section is not empty' using errcode = '55000';
  end if;
  if exists (select 1 from app.folder where parent_id = old.id) then
    raise exception 'section has child sections' using errcode = '55000';
  end if;
  return old;
end $$;

create or replace function app.reject_application_delete() returns trigger
language plpgsql as $$
begin
  raise exception 'applications are archived, not deleted' using errcode = '55000';
end $$;

create or replace function app.reject_document_delete() returns trigger
language plpgsql as $$
begin
  if exists (select 1 from app.document_version where document_id = old.id) then
    raise exception 'documents with versions are archived, not deleted' using errcode = '55000';
  end if;
  return old;
end $$;

drop trigger if exists matter_delete_guard on app.matter;
create trigger matter_delete_guard before delete on app.matter
  for each row execute function app.reject_delete();

drop trigger if exists folder_delete_guard on app.folder;
create trigger folder_delete_guard before delete on app.folder
  for each row execute function app.reject_nonempty_delete();

drop trigger if exists application_delete_guard on app.proceeding_application;
create trigger application_delete_guard before delete on app.proceeding_application
  for each row execute function app.reject_application_delete();

drop trigger if exists document_delete_guard on app.document;
create trigger document_delete_guard before delete on app.document
  for each row execute function app.reject_document_delete();

drop trigger if exists fact_position_append_only on app.fact_position;
create trigger fact_position_append_only before update or delete on app.fact_position
  for each row execute function app.reject_mutation();

drop trigger if exists evidence_status_append_only on app.evidence_status;
create trigger evidence_status_append_only before update or delete on app.evidence_status
  for each row execute function app.reject_mutation();

drop trigger if exists registry_event_append_only on app.registry_event;
create trigger registry_event_append_only before update or delete on app.registry_event
  for each row execute function app.reject_mutation();

create or replace function app.reject_exhibit_no_change() returns trigger
language plpgsql as $$
begin
  if old.exhibit_no is distinct from new.exhibit_no then
    raise exception 'exhibit number is append-only' using errcode = '55000';
  end if;
  return new;
end $$;
drop trigger if exists exhibit_no_append_only on app.exhibit;
create trigger exhibit_no_append_only before update on app.exhibit
  for each row execute function app.reject_exhibit_no_change();

-- ---------------------------------------------------------------------------
-- New table ownership and grants
-- ---------------------------------------------------------------------------
insert into ops.table_owner (table_name, module) values
  ('user_credential','identity'),
  ('delegation','identity'),
  ('matter_close','matter')
on conflict (table_name) do update set module = excluded.module;

grant select, insert, update, delete on app.delegation, app.matter_close to maverick_app;
grant select on app.delegation, app.matter_close to maverick_readonly;
revoke all on app.user_credential from maverick_app, maverick_readonly;
grant select, insert, update, delete on app.user_credential to maverick_owner;

-- Restricted-document children must not fall back to the generic Matter edit
-- policy; their access follows the document or version grant.
drop policy if exists document_write on app.document;
drop policy if exists document_version_write on app.document_version;

drop policy if exists document_text_access on app.document_text;
drop policy if exists document_text_read on app.document_text;
drop policy if exists document_text_write on app.document_text;
create policy document_text_read on app.document_text for select
  using (app.has_document_version_access(document_version_id, 'view'));
create policy document_text_write on app.document_text for all
  using (app.has_document_version_access(document_version_id, 'edit'))
  with check (app.has_document_version_access(document_version_id, 'edit'));

drop policy if exists document_anchor_access on app.document_anchor;
drop policy if exists document_anchor_read on app.document_anchor;
drop policy if exists document_anchor_write on app.document_anchor;
create policy document_anchor_read on app.document_anchor for select
  using (app.has_document_version_access(document_version_id, 'view'));
create policy document_anchor_write on app.document_anchor for all
  using (app.has_document_version_access(document_version_id, 'edit'))
  with check (app.has_document_version_access(document_version_id, 'edit'));

drop policy if exists document_chunk_access on app.document_chunk;
drop policy if exists document_chunk_read on app.document_chunk;
drop policy if exists document_chunk_write on app.document_chunk;
create policy document_chunk_read on app.document_chunk for select
  using (app.has_document_version_access(document_version_id, 'view'));
create policy document_chunk_write on app.document_chunk for all
  using (app.has_document_version_access(document_version_id, 'edit'))
  with check (app.has_document_version_access(document_version_id, 'edit'));

drop policy if exists annotation_access on app.annotation;
drop policy if exists annotation_read on app.annotation;
drop policy if exists annotation_write on app.annotation;
create policy annotation_read on app.annotation for select
  using (app.has_document_version_access(document_version_id, 'view'));
create policy annotation_insert on app.annotation for insert
  with check (
    app.has_document_version_access(document_version_id, 'view')
    and author_id = app.current_user()
  );
create policy annotation_update on app.annotation for update
  using (author_id = app.current_user())
  with check (author_id = app.current_user());
create policy annotation_delete on app.annotation for delete
  using (author_id = app.current_user());

drop policy if exists document_relation_access on app.document_relation;
drop policy if exists document_relation_read on app.document_relation;
drop policy if exists document_relation_write on app.document_relation;
create policy document_relation_read on app.document_relation for select
  using (app.has_document_relation_access(from_document_id, to_document_id));
create policy document_relation_write on app.document_relation for all
  using (
    app.has_document_access(from_document_id, 'edit')
    and app.has_document_access(to_document_id, 'edit')
  )
  with check (
    app.has_document_access(from_document_id, 'edit')
    and app.has_document_access(to_document_id, 'edit')
  );

-- Membership: a delegate with settings may manage non-admin members; only an
-- admin may create, modify or remove an admin.
drop policy if exists membership_self on app.membership;
drop policy if exists membership_admin on app.membership;
drop policy if exists membership_read on app.membership;
drop policy if exists membership_write on app.membership;
create policy membership_read on app.membership for select
  using (
    user_id = app.current_user()
    or app.is_admin()
    or app.is_delegate('settings')
  );
create policy membership_write on app.membership for all
  using (app.is_admin() or app.is_delegate('settings'))
  with check (app.is_admin() or app.is_delegate('settings'));

create or replace function app.reject_delegate_admin_role() returns trigger
language plpgsql as $$
begin
  if current_user = 'maverick_owner' then
    return new;
  end if;
  if not app.is_admin() and new.role = 'admin' then
    raise exception 'only an admin may promote an admin' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and old.role = 'admin' and not app.is_admin() then
    raise exception 'only an admin may modify an admin' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists membership_admin_guard on app.membership;
create trigger membership_admin_guard before insert or update on app.membership
  for each row execute function app.reject_delegate_admin_role();
alter function app.reject_delegate_admin_role() owner to maverick_owner;
