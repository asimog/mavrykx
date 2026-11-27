"""Authorise and execute agent tool calls against application services."""

from __future__ import annotations

from collections.abc import Mapping, Sequence

from pydantic import BaseModel

from mavrykx.application.registry import Operation


class UnknownOperation(RuntimeError):
    """The operation id is not in the catalog."""


class HumanOnlyOperation(RuntimeError):
    """The operation requires a human and is never a tool."""


class ToolGateway:
    """The one agent door: resolve, authorise, validate and call one service operation."""

    def __init__(self, operations: Sequence[Operation]) -> None:
        self._operations = {operation.id: operation for operation in operations}

    def call(self, operation_id: str, arguments: Mapping[str, object]) -> BaseModel:
        operation = self._operations.get(operation_id)
        if operation is None:
            raise UnknownOperation(operation_id)
        if operation.human_only:
            raise HumanOnlyOperation(operation_id)
        request = operation.input_model.model_validate(arguments)
        result = operation.call(request)
        return operation.output_model.model_validate(result)
