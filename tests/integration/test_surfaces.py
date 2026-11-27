import json

from fastapi.testclient import TestClient
from typer.testing import CliRunner

from mavrykx import __version__
from mavrykx.application.contracts import SystemStatus
from mavrykx.application.registry import OPERATIONS
from mavrykx.application.system import SystemService
from mavrykx.gateway.service import ToolGateway
from mavrykx.interfaces.api.app import build_app
from mavrykx.interfaces.cli.app import build_cli
from mavrykx.interfaces.tools.catalog import TOOLS
from mavrykx.interfaces.tools.context import ToolContext


def test_http_status() -> None:
    client = TestClient(build_app(SystemService()))
    response = client.get("/system/status")
    assert response.status_code == 200
    assert response.json() == {"name": "MavrykX", "version": __version__}


def test_cli_status() -> None:
    result = CliRunner().invoke(build_cli(SystemService()), ["system", "status"])
    assert result.exit_code == 0
    assert json.loads(result.stdout) == {"name": "MavrykX", "version": __version__}


def test_tool_status() -> None:
    gateway = ToolGateway(OPERATIONS)
    result = TOOLS[0].function(ToolContext(gateway=gateway))
    assert isinstance(result, SystemStatus)
    assert result == SystemStatus(name="MavrykX", version=__version__)
