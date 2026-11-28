"""The baseline SQL that revision 0001 executes, and the digest of its bytes."""

from __future__ import annotations

import hashlib
from pathlib import Path

BASELINE = Path(__file__).resolve().parents[1] / "docs" / "v1" / "schema" / "0001_core.sql"
SHA256 = "202fe3597e0239042e430c855cee87476d164e7e86d81fa95e35295f0dd41a5d"


def digest(source: bytes) -> str:
    """Hash the baseline as content, so a checkout's line endings cannot change the answer."""
    return hashlib.sha256(source.replace(b"\r\n", b"\n")).hexdigest()
