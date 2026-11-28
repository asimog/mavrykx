"""The failure vocabulary is closed: an unknown code cannot be raised."""

from __future__ import annotations

import pytest

from mavrykx.application.errors import ApplicationError, ErrorCode
from mavrykx.application.registry import OPERATIONS, Operation


def test_an_unknown_error_code_is_refused() -> None:
    with pytest.raises(ValueError, match="NOPE"):
        ErrorCode("NOPE")


def test_an_error_carries_its_code_and_replay_safety() -> None:
    error = ApplicationError(
        ErrorCode.EFFECT_UNCERTAIN, "the effect may have landed", effect_uncertain=True
    )

    assert error.code is ErrorCode.EFFECT_UNCERTAIN
    assert error.retryable is False
    assert error.effect_uncertain is True
    assert str(error) == "the effect may have landed"


def test_every_operation_has_a_stable_dotted_id() -> None:
    assert OPERATIONS
    for operation in OPERATIONS:
        assert isinstance(operation, Operation)
        assert operation.id.count(".") == 1
        assert operation.id == operation.id.lower()
        assert operation.summary.endswith(".")
