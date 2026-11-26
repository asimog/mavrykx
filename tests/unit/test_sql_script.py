from migrations.sql_script import split_statements


def test_splits_simple_statements() -> None:
    assert split_statements("select 1; select 2;") == ["select 1", "select 2"]


def test_keeps_dollar_quoted_bodies() -> None:
    source = "create function f() returns int language sql as $$ select 1; $$;\nselect 2;"
    statements = split_statements(source)
    assert len(statements) == 2
    assert statements[0].endswith("$$")
    assert statements[1] == "select 2"


def test_keeps_tagged_dollar_quotes() -> None:
    source = "do $body$ begin perform 1; end $body$; select 3;"
    assert len(split_statements(source)) == 2


def test_keeps_semicolons_in_strings_and_comments() -> None:
    source = "select 'a;b'; -- one; two\nselect 2;"
    assert len(split_statements(source)) == 2


def test_keeps_semicolons_in_quoted_identifiers() -> None:
    source = 'create table "a;b" (id int); select 1;'
    assert len(split_statements(source)) == 2


def test_handles_escaped_single_quotes() -> None:
    assert split_statements("select 'it''s; fine';") == ["select 'it''s; fine'"]


def test_skips_empty_statements() -> None:
    assert split_statements("; ;\n") == []
