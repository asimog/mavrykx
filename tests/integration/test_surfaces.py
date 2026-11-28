import json

from fastapi.testclient import TestClient
from typer.testing import CliRunner

from mavrykx import __version__
from mavrykx.application.contracts import SystemStatus
from mavrykx.application.system import SystemService
from mavrykx.composition.operations import OPERATIONS
from mavrykx.domain.actor import Actor
from mavrykx.gateway.service import ToolGateway
from mavrykx.infrastructure.unit_of_work import SqlAlchemyUnitOfWork
from mavrykx.interfaces.api.app import build_app
from mavrykx.interfaces.cli.app import build_cli
from mavrykx.interfaces.tools.catalog import TOOLS
from mavrykx.interfaces.tools.context import ToolContext
from mavrykx.modules.identity.api import IdentityService


def _unavailable(_actor: Actor) -> SqlAlchemyUnitOfWork:
    raise RuntimeError("the surface test does not open a transaction")


def _identity() -> IdentityService:
    return IdentityService(_unavailable)


def test_http_status() -> None:
    client = TestClient(build_app(SystemService(), _identity()))
    response = client.get("/system/status")
    assert response.status_code == 200
    assert response.json() == {"name": "MavrykX", "version": __version__}


def test_http_identity_requires_a_session() -> None:
    client = TestClient(build_app(SystemService(), _identity()))
    response = client.post(
        "/identity/users",
        json={"email": "a@b.co", "display_name": "A", "role": "staff"},
    )
    assert response.status_code == 401
    assert response.json()["code"] == "AUTH_INVALID"


def test_cli_status() -> None:
    result = CliRunner().invoke(build_cli(SystemService(), _identity()), ["system", "status"])
    assert result.exit_code == 0
    assert json.loads(result.stdout) == {"name": "MavrykX", "version": __version__}


def test_tool_status() -> None:
    gateway = ToolGateway(OPERATIONS)
    result = TOOLS[0].function(ToolContext(gateway=gateway))
    assert isinstance(result, SystemStatus)
    assert result == SystemStatus(name="MavrykX", version=__version__)
