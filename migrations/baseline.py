"""The baseline SQL that revision 0001 executes, and the digest of its bytes."""

from __future__ import annotations

from pathlib import Path

BASELINE = Path(__file__).resolve().parents[1] / "docs" / "v1" / "schema" / "0001_core.sql"
SHA256 = "03bb5446caea7b52877594f681995f588e34048e363551bd25c33468869ef9a2"
