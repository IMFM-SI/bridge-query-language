"""The MathQL query tools: `query`, `describe`, `grammar`, and the grammar resource."""

from pathlib import Path
from typing import Any, Literal, cast

from mcp.server.fastmcp import FastMCP

from mathql_mcp.engine import Engine


def register(
    mcp: FastMCP,
    engines: dict[str, Engine],
    schemas: dict[str, dict[str, Any]],
    grammar_path: Path,
) -> None:
    """Register the query tools and the grammar resource on `mcp`."""

    default = next(iter(engines), None)

    def resolve(database: str | None) -> str:
        name = database if database is not None else default
        if name in engines:
            return name
        else:
            raise ValueError(
                f"unknown database '{name}'; available: {', '.join(engines)}"
            )

    def read_grammar() -> str:
        return grammar_path.read_text()

    @mcp.tool()
    def query(
        domains: list[tuple[str, str]],
        output: list[tuple[str, str]],
        condition: str | None = None,
        order: list[tuple[str, Literal["asc", "desc"]]] | None = None,
        limit: int | None = None,
        postprocess: list[tuple[str, str]] | None = None,
        database: str | None = None,
    ) -> list[list[tuple[str, Any]]]:
        """Run a MathQL query and return the matching rows.

        Each row is a list of [column name, value] pairs: the output columns in their
        given order, then the postprocess columns in theirs.

        domains: variable bindings, e.g. [["g", "Graph"]].
        output: [column name, expression] pairs, in the order the columns are to
            appear, e.g. [["g6", "id(g)"], ["edges", "g.num_edges"]]. Each
            expression is over the bound variables (see the grammar tool).
        condition: a boolean expression over the bound variables (optional).
        order: [expression, "asc"|"desc"] pairs; the expressions may refer to the
            output column names (optional).
        limit: maximum number of rows (optional).
        postprocess: [column name, expression] pairs appended to each row and
            computed in order after the rows come back, each expression over the
            output columns and any earlier entry (optional).
        database: which database to query (optional; `describe` with an empty argument
            list returns the list, the first entry being the default).
        """
        request: dict[str, Any] = {"domains": domains, "output": output}
        if condition is not None:
            request["condition"] = condition
        if order is not None:
            request["order"] = order
        if limit is not None:
            request["limit"] = limit
        if postprocess is not None:
            request["postprocess"] = postprocess
        response = engines[resolve(database)].request(request)
        if "error" in response:
            raise ValueError(response["error"])
        return cast(list[list[tuple[str, Any]]], response["rows"])

    @mcp.tool()
    def describe(database: str | None = None) -> dict[str, Any]:
        """Describe a database: its domains, fields, constants, and examples.

        Called with an empty argument list, returns the available databases and their
        overviews.
        """
        if database is None:
            return {
                "databases": [
                    {"name": name, "overview": schemas[name].get("overview", "")}
                    for name in engines
                ]
            }
        else:
            return schemas[resolve(database)]

    @mcp.tool()
    def grammar() -> str:
        """The full query-language grammar: the JSON query shape, the expression grammar
        with precedence, the operator table, and examples."""
        return read_grammar()

    @mcp.resource("mathql://grammar")
    def grammar_resource() -> str:
        """The full MathQL query-language grammar."""
        return read_grammar()
