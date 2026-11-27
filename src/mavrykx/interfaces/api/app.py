"""Build the FastAPI application."""

from __future__ import annotations

from fastapi import FastAPI

from mavrykx.application.system import SystemService
from mavrykx.interfaces.api import system


def build_app(service: SystemService) -> FastAPI:
    app = FastAPI(title="MavrykX")
    app.dependency_overrides[system.get_system_service] = lambda: service
    app.include_router(system.router)
    return app
