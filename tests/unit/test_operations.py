from pathlib import Path

from fastapi import FastAPI
from pydantic import BaseModel
from typer import Typer

from mavrykx.application.registry import Operation
from mavrykx.application.system import SystemService
from mavrykx.composition.operations import OPERATIONS
from mavrykx.domain.actor import Actor
from mavrykx.infrastructure.unit_of_work import SqlAlchemyUnitOfWork
from mavrykx.interfaces.api.app import build_app
from mavrykx.interfaces.cli.app import build_cli
from mavrykx.interfaces.tools.catalog import TOOLS, ToolEntry
from mavrykx.modules.identity.api import IdentityService
from tools import operations

NEGATIVE = Path(__file__).resolve().parents[1] / "negative"


class _Empty(BaseModel):
    pass


def _call(_request: BaseModel) -> BaseModel:
    return _Empty()


def _unavailable(_actor: Actor) -> SqlAlchemyUnitOfWork:
    raise RuntimeError("the parity test never opens a transaction")


def _identity() -> IdentityService:
    return IdentityService(_unavailable)


def test_real_surfaces_have_parity() -> None:
    findings = operations.check_parity(
        OPERATIONS,
        build_app(SystemService(), _identity()),
        build_cli(SystemService(), _identity()),
        TOOLS,
    )
    assert findings == []


def test_real_interfaces_have_no_branches() -> None:
    assert operations.check_branches([operations.INTERFACES]) == []


def test_extra_route_fails_b3() -> None:
    app = FastAPI()

    @app.get("/extra", operation_id="system.extra")
    def extra() -> dict[str, str]:
        return {}

    findings = operations.check_parity((), app, Typer(), ())
    assert [finding.rule for finding in findings] == ["B3"]


def test_human_only_tool_fails_d2() -> None:
    operation = Operation(
        id="approval.grant",
        summary="Grant.",
        input_model=_Empty,
        output_model=_Empty,
        call=_call,
        surfaces=frozenset({"tool"}),
        human_only=True,
    )
    tools = (ToolEntry("approval.grant", lambda _context: _Empty()),)
    findings = operations.check_parity((operation,), FastAPI(), Typer(), tools)
    assert [finding.rule for finding in findings] == ["D2"]


def test_route_with_a_branch_fails_b2() -> None:
    findings = operations.check_branches([NEGATIVE / "operations" / "route_decision.py"])
    assert [finding.rule for finding in findings] == ["B2"]
