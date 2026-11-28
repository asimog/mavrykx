"""Build the FastAPI application."""

from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from mavrykx.application.errors import ApplicationError, ErrorCode
from mavrykx.application.system import SystemService
from mavrykx.interfaces.api import identity as identity_api
from mavrykx.interfaces.api import system as system_api
from mavrykx.modules.identity.api import IdentityService

STATUS_FOR_CODE = {
    ErrorCode.AUTH_INVALID: 401,
    ErrorCode.SESSION_REVOKED: 401,
    ErrorCode.USER_DISABLED: 403,
    ErrorCode.ROLE_FORBIDDEN: 403,
    ErrorCode.MATTER_ACCESS_DENIED: 403,
    ErrorCode.RESOURCE_ACCESS_DENIED: 403,
    ErrorCode.USER_NOT_FOUND: 404,
}


def _status(code: ErrorCode) -> int:
    return STATUS_FOR_CODE.get(code, 409)


def build_app(system_service: SystemService, identity_service: IdentityService) -> FastAPI:
    """Wire the routers and the services the composition root provides."""
    app = FastAPI(title="MavrykX")
    app.dependency_overrides[system_api.get_system_service] = lambda: system_service
    app.dependency_overrides[identity_api.get_identity_service] = lambda: identity_service
    app.include_router(system_api.router)
    app.include_router(identity_api.router)

    @app.exception_handler(ApplicationError)
    async def _application_error(_request: Request, error: ApplicationError) -> JSONResponse:
        return JSONResponse(
            status_code=_status(error.code),
            content={"code": error.code.value, "message": error.message},
        )

    return app
