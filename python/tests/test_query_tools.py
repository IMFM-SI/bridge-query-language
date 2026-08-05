"""Tests for the MCP tool layer, with the engine stubbed out.

The stub keeps these tests independent of the Lean build: what is under test is the
translation between an agent's call and the engine's JSON, which is where the tool
layer's own defects live.
"""

import asyncio
import pathlib
from typing import Any

import pytest
from mcp.server.fastmcp import FastMCP

from mathql_mcp import query_tools

GRAMMAR_PATH = pathlib.Path(__file__).resolve().parents[2] / "docs" / "query-grammar.md"

ROWS = [
    [["g6", "B?"], ["ds", [0, 0, 0]], ["dm", None]],
    [["g6", "BW"], ["ds", [2, 1, 1]], ["dm", 2]],
]


class StubEngine:
    """An engine that records each request and replies with `ROWS`."""

    def __init__(self) -> None:
        self.requests: list[dict[str, Any]] = []

    def request(self, obj: dict[str, Any]) -> dict[str, Any]:
        self.requests.append(obj)
        return {"rows": ROWS}


def build() -> tuple[FastMCP, StubEngine]:
    """A FastMCP app whose one database is a `StubEngine`."""
    engine = StubEngine()
    app = FastMCP("test")
    query_tools.register(app, {"db": engine}, {"db": {}}, GRAMMAR_PATH)  # type: ignore[dict-item]
    return app, engine


def structured(result: object) -> object:
    """The structured content of a `call_tool` result."""
    return result[1] if isinstance(result, tuple) else None


def test_query_declares_an_output_schema() -> None:
    app, _ = build()
    tool = next(t for t in asyncio.run(app.list_tools()) if t.name == "query")
    assert tool.outputSchema is not None


def test_rows_keep_their_pairs_nulls_and_lists() -> None:
    app, _ = build()
    result = asyncio.run(
        app.call_tool(
            "query",
            {
                "domains": [["g", "Graph"]],
                "output": [["g6", "g.graph6"], ["ds", "g.degree_sequence"], ["dm", "g.diameter"]],
            },
        )
    )
    assert structured(result) == {"result": ROWS}


def test_output_order_is_preserved_in_the_request() -> None:
    app, engine = build()
    asyncio.run(
        app.call_tool(
            "query",
            {"domains": [["g", "Graph"]], "output": [["zeta", "g.n"], ["alpha", "g.m"]]},
        )
    )
    assert engine.requests[-1]["output"] == [("zeta", "g.n"), ("alpha", "g.m")]


def test_postprocess_reaches_the_engine() -> None:
    app, engine = build()
    asyncio.run(
        app.call_tool(
            "query",
            {
                "domains": [["g", "Graph"]],
                "output": [["n", "g.n"]],
                "postprocess": [["k", "n + 1"]],
            },
        )
    )
    assert engine.requests[-1]["postprocess"] == [("k", "n + 1")]


def test_an_absent_clause_is_left_out_of_the_request() -> None:
    app, engine = build()
    asyncio.run(
        app.call_tool("query", {"domains": [["g", "Graph"]], "output": [["n", "g.n"]]})
    )
    assert set(engine.requests[-1]) == {"domains", "output"}


def test_a_bad_order_direction_never_reaches_the_engine() -> None:
    app, engine = build()
    with pytest.raises(Exception):  # noqa: B017
        asyncio.run(
            app.call_tool(
                "query",
                {
                    "domains": [["g", "Graph"]],
                    "output": [["n", "g.n"]],
                    "order": [["n", "sideways"]],
                },
            )
        )
    assert engine.requests == []


def test_a_three_element_output_entry_never_reaches_the_engine() -> None:
    app, engine = build()
    with pytest.raises(Exception):  # noqa: B017
        asyncio.run(
            app.call_tool(
                "query",
                {"domains": [["g", "Graph"]], "output": [["n", "g.n", "extra"]]},
            )
        )
    assert engine.requests == []


def test_an_unknown_database_is_reported() -> None:
    app, _ = build()
    with pytest.raises(Exception):  # noqa: B017
        asyncio.run(
            app.call_tool(
                "query",
                {
                    "domains": [["g", "Graph"]],
                    "output": [["n", "g.n"]],
                    "database": "nosuch",
                },
            )
        )
