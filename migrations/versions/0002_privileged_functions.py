"""Privileged bootstrap and credential functions owned by maverick_owner.

The application role never reads `app.user_credential` and never inserts the first firm. Both happen
inside security-definer functions, so the owner password never leaves the database.
"""

from __future__ import annotations

from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None

STATEMENTS = (
    "alter role maverick_owner bypassrls",
    "grant usage on schema app to maverick_owner",
    "grant select, insert, update, delete on all tables in schema app to maverick_owner",
    "grant usage, select on all sequences in schema app to maverick_owner",
    """
    create or replace function app.create_firm(
      p_firm_name text,
      p_jurisdiction text,
      p_admin_email text,
      p_admin_display_name text
    ) returns uuid
    language plpgsql
    security definer
    set search_path = app, public, pg_temp
    as $$
    declare
      v_firm uuid;
      v_user uuid;
    begin
      if exists (select 1 from app.firm) then
        raise exception 'FIRM_EXISTS' using errcode = 'P0001';
      end if;
      insert into app.firm (name, jurisdiction)
        values (p_firm_name, p_jurisdiction) returning id into v_firm;
      insert into app.user (email, display_name, status)
        values (p_admin_email, p_admin_display_name, 'invited') returning id into v_user;
      insert into app.membership (user_id, firm_id, role)
        values (v_user, v_firm, 'admin');
      return v_firm;
    end;
    $$
    """,
    "alter function app.create_firm(text, text, text, text) owner to maverick_owner",
    "revoke all on function app.create_firm(text, text, text, text) from public",
    "grant execute on function app.create_firm(text, text, text, text) to maverick_app",
    """
    create or replace function app.set_credential(p_user_id uuid, p_password text)
    returns void
    language sql
    security definer
    set search_path = app, public, pg_temp
    as $$
      insert into app.user_credential (user_id, password_hash)
        values (p_user_id, crypt(p_password, gen_salt('bf', 12)))
      on conflict (user_id) do update
        set password_hash = excluded.password_hash, updated_at = now();
      update app.user set status = 'active', updated_at = now() where id = p_user_id;
    $$
    """,
    "alter function app.set_credential(uuid, text) owner to maverick_owner",
    "revoke all on function app.set_credential(uuid, text) from public",
    "grant execute on function app.set_credential(uuid, text) to maverick_app",
    """
    create or replace function app.authenticate(p_email text, p_password text)
    returns table (user_id uuid, firm_id uuid, role text)
    language plpgsql
    security definer
    set search_path = app, public, pg_temp
    as $$
    declare
      v_user uuid;
      v_status text;
      v_hash text;
      v_firm uuid;
      v_role text;
    begin
      select u.id, u.status, c.password_hash, m.firm_id, m.role
        into v_user, v_status, v_hash, v_firm, v_role
      from app.user u
      join app.user_credential c on c.user_id = u.id
      join app.membership m on m.user_id = u.id and m.disabled_at is null
      where lower(u.email) = lower(p_email);

      if v_user is null or v_hash is null or crypt(p_password, v_hash) <> v_hash then
        raise exception 'AUTH_INVALID' using errcode = 'P0001';
      end if;
      if v_status <> 'active' then
        raise exception 'USER_DISABLED' using errcode = 'P0001';
      end if;
      return query select v_user, v_firm, v_role;
    end;
    $$
    """,
    "alter function app.authenticate(text, text) owner to maverick_owner",
    "revoke all on function app.authenticate(text, text) from public",
    "grant execute on function app.authenticate(text, text) to maverick_app",
    """
    create or replace function app.create_session(
      p_user_id uuid, p_token_hash text, p_expires_at timestamptz
    ) returns uuid
    language plpgsql
    security definer
    set search_path = app, public, pg_temp
    as $$
    declare
      v_id uuid;
    begin
      insert into app.session (user_id, token_hash, expires_at)
        values (p_user_id, p_token_hash, p_expires_at) returning id into v_id;
      return v_id;
    end;
    $$
    """,
    "alter function app.create_session(uuid, text, timestamptz) owner to maverick_owner",
    "revoke all on function app.create_session(uuid, text, timestamptz) from public",
    "grant execute on function app.create_session(uuid, text, timestamptz) to maverick_app",
    """
    create or replace function app.session_actor(p_token_hash text)
    returns table (user_id uuid, firm_id uuid)
    language sql
    security definer
    set search_path = app, public, pg_temp
    as $$
      select s.user_id, m.firm_id
      from app.session s
      join app.membership m on m.user_id = s.user_id and m.disabled_at is null
      join app.user u on u.id = s.user_id and u.status = 'active'
      where s.token_hash = p_token_hash
        and s.revoked_at is null
        and s.expires_at > now();
    $$
    """,
    "alter function app.session_actor(text) owner to maverick_owner",
    "revoke all on function app.session_actor(text) from public",
    "grant execute on function app.session_actor(text) to maverick_app",
    """
    create or replace function app.revoke_session(p_token_hash text)
    returns boolean
    language plpgsql
    security definer
    set search_path = app, public, pg_temp
    as $$
    begin
      update app.session set revoked_at = now()
        where token_hash = p_token_hash and revoked_at is null;
      return found;
    end;
    $$
    """,
    "alter function app.revoke_session(text) owner to maverick_owner",
    "revoke all on function app.revoke_session(text) from public",
    "grant execute on function app.revoke_session(text) to maverick_app",
)


def upgrade() -> None:
    for statement in STATEMENTS:
        op.execute(statement)


def downgrade() -> None:
    raise NotImplementedError("MavrykX migrations are forward-only")
