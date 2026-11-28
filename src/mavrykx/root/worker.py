"""The composition root for the worker role: ingest, OCR and scheduled jobs."""

from __future__ import annotations


def main() -> None:
    """Start the durable job loop.

    Raises:
        NotImplementedError: the job loop arrives with the first queue consumer.
    """
    raise NotImplementedError(
        "mavrykx-worker has no job loop yet; add the PostgreSQL queue consumer"
    )
