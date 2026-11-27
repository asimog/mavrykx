from pathlib import Path

from fastapi import FastAPI
from pydantic import BaseModel
from typer import Typer

from mavrykx.application.registry import OPERATIONS, Operation
from mavrykx.application.system import SystemService
from mavrykx.interfaces.api.app import build_app
from mavrykx.interfaces.cli.app import build_cli
from mavrykx.interfaces.tools.catalog import TOOLS, ToolEntry
from tools import operations

NEGATIVE = Path(__file__).resolve().parents[1] / "negative"


class _Empty(BaseModel):
    pass


def _call(_request: BaseModel) -> BaseModel:
    return _Empty()


def test_real_surfaces_have_parity() -> None:
    findings = operations.check_parity(
        OPERATIONS, build_app(SystemService()), build_cli(SystemService()), TOOLS
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
