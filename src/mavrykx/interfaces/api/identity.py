"""The identity HTTP surface."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Header

from mavrykx.domain.actor import Actor
from mavrykx.modules.identity.api import (
    FirmInitRequest,
    FirmView,
    IdentityService,
    MembershipSetRoleRequest,
    MembershipView,
    SessionCreateRequest,
    SessionRevoked,
    SessionRevokeRequest,
    SessionView,
    UserDisableRequest,
    UserInviteRequest,
    UserView,
)

router = APIRouter(prefix="/identity", tags=["identity"])


def get_identity_service() -> IdentityService:
    """The composition root overrides this dependency."""
    raise RuntimeError("IdentityService is wired by the composition root")


Service = Annotated[IdentityService, Depends(get_identity_service)]


async def get_actor(
    service: Service,
    authorization: Annotated[str | None, Header()] = None,
) -> Actor:
    """Resolve the acting user from the bearer token."""
    return await service.actor_from_header(authorization)


ActorDep = Annotated[Actor, Depends(get_actor)]


@router.post("/firm", response_model=FirmView, operation_id="firm.init")
async def init_firm(request: FirmInitRequest, service: Service) -> FirmView:
    return await service.init_firm(request)


@router.post("/users", response_model=UserView, operation_id="user.invite")
async def invite_user(request: UserInviteRequest, actor: ActorDep, service: Service) -> UserView:
    return await service.invite(actor, request)


@router.post("/users/disable", response_model=UserView, operation_id="user.disable")
async def disable_user(
    request: UserDisableRequest, actor: ActorDep, service: Service
) -> UserView:
    return await service.disable(actor, request)


@router.post("/memberships/role", response_model=MembershipView, operation_id="membership.set_role")
async def set_membership_role(
    request: MembershipSetRoleRequest, actor: ActorDep, service: Service
) -> MembershipView:
    return await service.set_role(actor, request)


@router.post("/sessions", response_model=SessionView, operation_id="session.create")
async def create_session(request: SessionCreateRequest, service: Service) -> SessionView:
    return await service.create_session(request)


@router.post("/sessions/revoke", response_model=SessionRevoked, operation_id="session.revoke")
async def revoke_session(request: SessionRevokeRequest, service: Service) -> SessionRevoked:
    return await service.revoke_session(request)
