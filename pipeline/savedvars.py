"""Minimal parser for WoW SavedVariables files (Lua table literals).

Supports what the client writes: `Name = { ... }` assignments, tables with
`["key"] = value`, `[number] = value` and positional values, strings with
Lua escapes, numbers, true/false/nil. Not a general Lua parser.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any

_TOKEN = re.compile(
    r"""
    (?P<ws>\s+|--[^\n]*) |
    (?P<str>"(?:\\.|[^"\\])*") |
    (?P<num>-?(?:0x[0-9a-fA-F]+|\d+(?:\.\d*)?(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?)) |
    (?P<name>[A-Za-z_][A-Za-z0-9_]*) |
    (?P<sym>[{}\[\]=,;])
    """,
    re.VERBOSE,
)

_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}


def _unescape(body: str) -> str:
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        nxt = body[i + 1]
        if nxt.isdigit():  # \ddd decimal byte
            m = re.match(r"\d{1,3}", body[i + 1:])
            out.append(chr(int(m.group())))
            i += 1 + len(m.group())
        else:
            out.append(_ESCAPES.get(nxt, nxt))
            i += 2
    return "".join(out)


def _tokenize(text: str):
    pos = 0
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m:
            raise ValueError(f"unexpected character at {pos}: {text[pos:pos + 30]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind == "ws":
            continue
        yield kind, m.group()


class _Parser:
    def __init__(self, text: str):
        self.tokens = list(_tokenize(text))
        self.i = 0

    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else (None, None)

    def take(self, expected: str | None = None):
        tok = self.peek()
        if expected is not None and tok[1] != expected:
            raise ValueError(f"expected {expected!r}, got {tok!r} at token {self.i}")
        self.i += 1
        return tok

    def value(self) -> Any:
        kind, text = self.peek()
        if text == "{":
            return self.table()
        self.take()
        if kind == "str":
            return _unescape(text[1:-1])
        if kind == "num":
            v = float(int(text, 16)) if text.lower().startswith(("0x", "-0x")) else float(text)
            return int(v) if v.is_integer() and "." not in text and "e" not in text.lower() else v
        if kind == "name":
            return {"true": True, "false": False, "nil": None}[text]
        raise ValueError(f"unexpected token {text!r}")

    def table(self) -> dict | list:
        self.take("{")
        result: dict[Any, Any] = {}
        n = 1
        while self.peek()[1] != "}":
            if self.peek()[1] == "[":
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                result[key] = self.value()
            else:
                v = self.value()
                if v is not None:  # the client writes `nil,` as array-hole padding
                    result[n] = v
                n += 1
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        return result

    def document(self) -> dict[str, Any]:
        out = {}
        while self.peek()[0] is not None:
            _, name = self.take()
            self.take("=")
            out[name] = self.value()
        return out


def load(path: str | Path) -> dict[str, Any]:
    """Parse a SavedVariables file into {globalName: value}. Tables become dicts."""
    return _Parser(Path(path).read_text(encoding="utf-8")).document()


if __name__ == "__main__":
    data = load(sys.argv[1])
    print({k: type(v).__name__ for k, v in data.items()})
