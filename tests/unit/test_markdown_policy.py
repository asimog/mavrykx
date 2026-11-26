from pathlib import Path

from tools import markdown_policy


def _write(directory: Path, name: str, title: str) -> Path:
    path = directory / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"# {title}\n", encoding="utf-8")
    return path


def test_unlisted_file_fails_c1(tmp_path: Path) -> None:
    path = _write(tmp_path, "notes.md", "Notes")
    findings = markdown_policy.check(tmp_path, paths=[path], allowlist={})
    assert [finding.rule for finding in findings] == ["C1"]


def test_banned_filename_fails_c2(tmp_path: Path) -> None:
    path = _write(tmp_path, "FINAL-architecture.md", "Architecture")
    findings = markdown_policy.check(
        tmp_path,
        paths=[path],
        allowlist={"FINAL-architecture.md": "fixture"},
    )
    assert [finding.rule for finding in findings] == ["C2"]


def test_duplicate_title_fails_c3(tmp_path: Path) -> None:
    first = _write(tmp_path, "one.md", "Same")
    second = _write(tmp_path, "two.md", "Same")
    findings = markdown_policy.check(
        tmp_path,
        paths=[first, second],
        allowlist={"one.md": "fixture", "two.md": "fixture"},
    )
    assert [finding.rule for finding in findings] == ["C3"]


def test_allowlisted_file_passes(tmp_path: Path) -> None:
    path = _write(tmp_path, "notes.md", "Notes")
    findings = markdown_policy.check(
        tmp_path,
        paths=[path],
        allowlist={"notes.md": "fixture"},
    )
    assert findings == []
