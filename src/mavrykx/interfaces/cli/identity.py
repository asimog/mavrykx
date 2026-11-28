"""The identity CLI surface: one command per registry id."""

from __future__ import annotations

import asyncio
from typing import Annotated
from uuid import UUID

import typer

from mavrykx.domain.actor import Actor
from mavrykx.modules.identity.api import (
    FirmInitRequest,
    IdentityService,
    MembershipSetRoleRequest,
    Role,
    SessionCreateRequest,
    SessionRevokeRequest,
    UserDisableRequest,
    UserInviteRequest,
)

ActorOption = Annotated[UUID, typer.Option(help="The acting admin's user id.")]


def build_identity_cli(service: IdentityService) -> typer.Typer:
    """Build the firm, user and membership command groups."""
    app = typer.Typer(help="Firm, user and membership commands.")
    firm = typer.Typer(help="Firm commands.")
    user = typer.Typer(help="User commands.")
    membership = typer.Typer(help="Membership commands.")

    @firm.command("init")
    def init_firm(
        firm_name: str,
        admin_email: str,
        admin_display_name: str,
        jurisdiction: str | None = None,
    ) -> None:
        """Open the installation with its firm and first admin."""
        request = FirmInitRequest(
            firm_name=firm_name,
            admin_email=admin_email,
            admin_display_name=admin_display_name,
            jurisdiction=jurisdiction,
        )
        typer.echo(asyncio.run(service.init_firm(request)).model_dump_json())

    @user.command("invite")
    def invite_user(
        email: str,
        display_name: str,
        role: Role,
        actor: ActorOption,
        title: str | None = None,
    ) -> None:
        """Invite a user and give them their role."""
        request = UserInviteRequest(
            email=email, display_name=display_name, role=role, title=title
        )
        result = asyncio.run(service.invite(Actor(user_id=actor), request))
        typer.echo(result.model_dump_json())

    @user.command("disable")
    def disable_user(user_id: UUID, actor: ActorOption) -> None:
        """Disable a user."""
        request = UserDisableRequest(user_id=user_id)
        result = asyncio.run(service.disable(Actor(user_id=actor), request))
        typer.echo(result.model_dump_json())

    @membership.command("set_role")
    def set_role(user_id: UUID, role: Role, actor: ActorOption) -> None:
        """Change a user's role."""
        request = MembershipSetRoleRequest(user_id=user_id, role=role)
        result = asyncio.run(service.set_role(Actor(user_id=actor), request))
        typer.echo(result.model_dump_json())

    session = typer.Typer(help="Session commands.")

    @session.command("create")
    def create_session(email: str, password: str) -> None:
        """Sign in and print a session token."""
        request = SessionCreateRequest(email=email, password=password)
        typer.echo(asyncio.run(service.create_session(request)).model_dump_json())

    @session.command("revoke")
    def revoke_session(token: str) -> None:
        """Revoke a session token."""
        request = SessionRevokeRequest(token=token)
        typer.echo(asyncio.run(service.revoke_session(request)).model_dump_json())

    app.add_typer(firm, name="firm")
    app.add_typer(user, name="user")
    app.add_typer(membership, name="membership")
    app.add_typer(session, name="session")
    return app
