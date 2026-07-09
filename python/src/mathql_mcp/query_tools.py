"""The MathQL query tools: `query`, `describe`, `grammar`, and the grammar resource."""

from pathlib import Path
from typing import Optional

from mcp.server.fastmcp import FastMCP

from mathql_mcp.engine import Engine


def register(mcp: FastMCP, engine: Engine, grammar_path: Path) -> None:
    """Register the query tools and the grammar resource on `mcp`."""

    def read_grammar() -> str:
        return grammar_path.read_text()

    @mcp.tool()
    def query(
        domains: list[list[str]],
        output: dict[str, str],
        condition: Optional[str] = None,
        order: Optional[list[list[str]]] = None,
        limit: Optional[int] = None,
    ) -> list:
        """Run a MathQL query and return the matching rows.

        domains: variable bindings, e.g. [["g", "Graph"]].
        output: a mapping from result column name to the expression it returns,
            e.g. {"g6": "id(g)", "edges": "g.num_edges"}. Each expression is over
            the bound variables (see the grammar tool).
        condition: a boolean expression over the bound variables (optional).
        order: [expression, "asc"|"desc"] pairs (optional).
        limit: maximum number of rows (optional).
        """
        request: dict = {"domains": domains, "output": output}
        if condition is not None:
            request["condition"] = condition
        if order is not None:
            request["order"] = order
        if limit is not None:
            request["limit"] = limit
        response = engine.request(request)
        if "error" in response:
            raise ValueError(response["error"])
        return response["rows"]

    @mcp.tool()
    def describe() -> dict:
        """Return the database schema: domains, fields, constants, and examples."""
        return engine.request({"describe": True})

    @mcp.tool()
    def grammar() -> str:
        """The full query-language grammar: the JSON query shape, the expression grammar
        with precedence, the operator table, and examples."""
        return read_grammar()

    @mcp.resource("mathql://grammar")
    def grammar_resource() -> str:
        """The full MathQL query-language grammar."""
        return read_grammar()
