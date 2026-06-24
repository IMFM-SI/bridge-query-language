"""An MCP server exposing MathQL to agents.

It offers two tools: `describe_schema`, to learn the available domains and
their invariants, and `query`, to run a MathQL query. Start it with the
`mathql-mcp` command (stdio transport).
"""

from __future__ import annotations

from typing import Any

from mcp.server.fastmcp import FastMCP

from mathql import catalog

server = FastMCP("mathql")


def _jsonable(value: Any) -> Any:
    """Turn query results into JSON-friendly values (tuples become lists)."""
    if isinstance(value, (list, tuple)):
        return [_jsonable(item) for item in value]
    if isinstance(value, dict):
        return {key: _jsonable(item) for key, item in value.items()}
    return value


@server.tool()
def query(query: str) -> list:
    """Run a MathQL query such as
    "{ g.num_edges for g in SmallGraphs if g.is_tree }" and return one result
    per object that satisfies it."""
    return _jsonable(catalog.run(query))


@server.tool()
def describe_schema() -> dict:
    """List the domains that can be queried and the invariants each provides."""
    return catalog.describe()


def main() -> None:
    server.run()
