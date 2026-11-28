"""The assembled operation catalogue: the application's own plus every module's."""

from __future__ import annotations

from mavrykx.application.registry import OPERATIONS as APPLICATION_OPERATIONS
from mavrykx.application.registry import Operation
from mavrykx.modules.identity.api import OPERATIONS as IDENTITY_OPERATIONS

OPERATIONS: tuple[Operation, ...] = APPLICATION_OPERATIONS + IDENTITY_OPERATIONS
