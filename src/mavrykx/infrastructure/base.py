"""The declarative base every module model shares."""

from __future__ import annotations

from sqlalchemy import MetaData
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """Metadata for module models. Alembic owns the schema, not this class."""

    metadata = MetaData(schema="app")
