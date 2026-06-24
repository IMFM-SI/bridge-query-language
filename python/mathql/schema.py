"""Description of a database: how its mathematical objects and their invariants
map onto stored data.

A `Domain` is a collection of mathematical objects (the unit an agent queries).
Each of its `Attribute`s is one invariant, described by the column that holds it
and a codec that decodes the stored cell into a Python value. A `Database`
groups the domains reachable through one SQLite file.
"""

from __future__ import annotations

from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class Attribute:
    """One invariant of a domain's objects. `column` is the SQL column holding
    it; `decode` turns a raw cell value into the Python value the query sees."""

    column: str
    decode: Callable[[Any], object]


@dataclass(frozen=True)
class Domain:
    """A collection of mathematical objects backed by one table. `attributes`
    maps invariant names to their descriptors; `represent` renders an object
    from its decoded attributes when a query returns the object itself."""

    table: str
    attributes: Mapping[str, Attribute]
    represent: Callable[[Mapping[str, object]], object]


@dataclass(frozen=True)
class Database:
    """A SQLite file together with the domains it exposes, keyed by domain name."""

    path: Path
    domains: Mapping[str, Domain]
