"""Password and token handling.

Passwords never reach this process: verification happens inside the database, through a
security-definer function owned by `maverick_owner`. This module only hashes session tokens.
"""

from __future__ import annotations

import hashlib
import secrets


def new_session_token() -> str:
    """Mint an opaque session token. Only its hash is stored."""
    return secrets.token_urlsafe(32)


def hash_session_token(token: str) -> str:
    """Hash a session token for storage and lookup."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()
