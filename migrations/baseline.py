"""The baseline SQL that revision 0001 executes, and the digest of its bytes."""

from __future__ import annotations

from pathlib import Path

BASELINE = Path(__file__).resolve().parents[1] / "docs" / "v1" / "schema" / "0001_core.sql"
SHA256 = "47220b2ee5272ec9dafbf52d53b7d806aec290d6387d7d557a3a4cd011772856"
