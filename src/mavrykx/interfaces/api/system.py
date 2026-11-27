"""The system HTTP surface."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from mavrykx.application.contracts import SystemStatus
from mavrykx.application.system import SystemService

router = APIRouter(prefix="/system", tags=["system"])


def get_system_service() -> SystemService:
    """The composition root overrides this dependency."""
    raise RuntimeError("SystemService is wired by the composition root")


@router.get("/status", response_model=SystemStatus, operation_id="system.status")
def read_status(service: Annotated[SystemService, Depends(get_system_service)]) -> SystemStatus:
    return service.status()
