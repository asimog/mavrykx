"""Split a SQL script into statements PostgreSQL accepts one at a time."""

from __future__ import annotations

import re

_IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")


def split_statements(source: str) -> list[str]:
    statements: list[str] = []
    start = 0
    index = 0
    length = len(source)
    state = "normal"
    dollar_tag = ""
    block_depth = 0

    while index < length:
        character = source[index]
        if state == "normal":
            if character == "'":
                state = "single"
                index += 1
            elif character == '"':
                state = "double"
                index += 1
            elif character == "-" and source[index + 1 : index + 2] == "-":
                state = "line"
                index += 2
            elif character == "/" and source[index + 1 : index + 2] == "*":
                state = "block"
                block_depth = 1
                index += 2
            elif character == "$":
                end = source.find("$", index + 1)
                if end != -1 and (end == index + 1 or _IDENTIFIER.match(source[index + 1 : end])):
                    dollar_tag = source[index : end + 1]
                    state = "dollar"
                    index = end + 1
                else:
                    index += 1
            elif character == ";":
                _append(statements, source, start, index)
                start = index + 1
                index += 1
            else:
                index += 1
        elif state == "single":
            if character == "'":
                if source[index + 1 : index + 2] == "'":
                    index += 2
                else:
                    state = "normal"
                    index += 1
            else:
                index += 1
        elif state == "double":
            if character == '"':
                if source[index + 1 : index + 2] == '"':
                    index += 2
                else:
                    state = "normal"
                    index += 1
            else:
                index += 1
        elif state == "line":
            if character == "\n":
                state = "normal"
            index += 1
        elif state == "block":
            if character == "/" and source[index + 1 : index + 2] == "*":
                block_depth += 1
                index += 2
            elif character == "*" and source[index + 1 : index + 2] == "/":
                block_depth -= 1
                index += 2
                if block_depth == 0:
                    state = "normal"
            else:
                index += 1
        elif source.startswith(dollar_tag, index):
            index += len(dollar_tag)
            state = "normal"
        else:
            index += 1

    _append(statements, source, start, length)
    return statements


def _append(statements: list[str], source: str, start: int, end: int) -> None:
    statement = source[start:end].strip()
    if statement:
        statements.append(statement)
