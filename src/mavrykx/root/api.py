"""The composition root for the HTTP surface."""

from __future__ import annotations

from mavrykx.application.system import SystemService
from mavrykx.interfaces.api.app import build_app

app = build_app(SystemService())
