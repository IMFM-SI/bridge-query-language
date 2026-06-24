"""The catalog of databases MathQL can query.

A query names a domain of objects, not a database; `run` finds the database
that provides that domain and executes the query there.
"""

from __future__ import annotations

from mathql import engine, schema
from mathql.databases.graphs import SMALL_GRAPHS
from mathql.databases.maniplexes import MANIPLEXES
from mathql.parser import parse

DATABASES: tuple[schema.Database, ...] = (SMALL_GRAPHS, MANIPLEXES)


def domains() -> dict[str, schema.Domain]:
    """Every domain in the catalog, keyed by name."""
    return {name: domain for database in DATABASES for name, domain in database.domains.items()}


def database_for(domain: str) -> schema.Database:
    """The database providing `domain`. Raises `KeyError` if none does."""
    for database in DATABASES:
        if domain in database.domains:
            return database
    raise KeyError(f"unknown domain {domain!r}; known domains: {', '.join(sorted(domains()))}")


def run(text: str) -> list[object]:
    """Execute a query against whichever catalog database provides its domain."""
    return engine.run(text, database_for(parse(text).domain))


def describe() -> dict[str, object]:
    """Every domain and the invariants it offers (name and kind), so a query can
    be written without knowing any storage details."""
    return {
        name: {
            "invariants": [
                {"name": invariant, "kind": attribute.kind}
                for invariant, attribute in domain.attributes.items()
            ]
        }
        for name, domain in domains().items()
    }
