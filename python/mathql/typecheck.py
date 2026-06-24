"""Type-checking of queries.

This is a stub: it accepts every query unchanged. A real implementation will
check that operators receive operands of compatible types and that every named
invariant exists in the domain.
"""

from __future__ import annotations

from mathql import schema, syntax


def typecheck(query: syntax.Query, domain: schema.Domain) -> syntax.Query:
    """Return the query unchanged. Always succeeds."""
    return query
