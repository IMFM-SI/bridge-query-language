"""Codecs decoding raw SQLite cell values into the Python values a query sees."""

from __future__ import annotations

import json
from typing import Any


def identity(value: Any) -> object:
    return value


def boolean(value: Any) -> object:
    return bool(value)


def optional_int(value: Any) -> object:
    return None if value is None else int(value)


def json_value(value: Any) -> object:
    """Decode a JSON text cell, e.g. a stored list such as `[4, 8, 8]`."""
    return json.loads(value)
