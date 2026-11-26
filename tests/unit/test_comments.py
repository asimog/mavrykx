from pathlib import Path

from tools import comments


def _rules(tmp_path: Path, name: str, source: str) -> list[str]:
    path = tmp_path / name
    path.write_text(source, encoding="utf-8")
    return [finding.rule for finding in comments.check(tmp_path, paths=[path])]


def test_routine_python_comment_fails(tmp_path: Path) -> None:
    assert _rules(tmp_path, "module.py", "value = 1  # increment\n") == ["A3"]


def test_python_directive_is_allowed(tmp_path: Path) -> None:
    assert _rules(tmp_path, "module.py", "value = 1  # type: ignore[assignment]\n") == []


def test_hash_inside_string_is_not_a_comment(tmp_path: Path) -> None:
    assert _rules(tmp_path, "module.py", 'value = "# not a comment"\n') == []


def test_routine_typescript_comment_fails(tmp_path: Path) -> None:
    assert _rules(tmp_path, "module.ts", "const value = 1 // increment\n") == ["A3"]


def test_double_slash_inside_string_is_not_a_comment(tmp_path: Path) -> None:
    assert _rules(tmp_path, "module.ts", 'const url = "https://example.com"\n') == []
