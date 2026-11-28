# MavrykX — Tests

- Unit tests live in `tests/unit`, integration in `tests/integration` and negative fixtures in `tests/negative`.
- Test behaviour at the highest seam. Prefer a service or API seam over a private function.
- Run the smallest file or case first: `uv run pytest tests/unit/test_x.py -q`.
- Add a negative fixture for a new boundary or permission rule.
- The RLS test needs `MAVRYKX_DATABASE_URL` and a disposable PostgreSQL database.
