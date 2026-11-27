"""Fixtures for the operations parity checks."""

from fastapi import FastAPI
from pydantic import BaseModel
from typer import Typer

from mavrykx.application.registry import Operation
from mavrykx.interfaces.tools.catalog import ToolEntry


class Empty(BaseModel):
    pass


def _call(_request: BaseModel) -> BaseModel:
    return Empty()


VALID = (
    Operation(
        id="system.status",
        summary="Status.",
        input_model=Empty,
        output_model=Empty,
        call=_call,
    ),
)

HUMAN = (
    Operation(
        id="approval.grant",
        summary="Grant.",
        input_model=Empty,
        output_model=Empty,
        call=_call,
        surfaces=frozenset({"tool"}),
        human_only=True,
    ),
)


def extra_api() -> FastAPI:
    app = FastAPI()

    @app.get("/system/status", operation_id="system.status")
    def status() -> Empty:
        return Empty()

    @app.get("/system/extra", operation_id="system.extra")
    def extra() -> Empty:
        return Empty()

    return app


def empty_api() -> FastAPI:
    return FastAPI()


def empty_cli() -> Typer:
    return Typer()


def human_tools() -> tuple[ToolEntry, ...]:
    return (ToolEntry("approval.grant", lambda _context: Empty()),)
