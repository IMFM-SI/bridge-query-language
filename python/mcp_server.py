#!/usr/bin/env python3
"""MCP server exposing the MathQL Lean engine to agents.

It forwards the `query` and `describe_schema` tools to the compiled `mathql`
executable: `query` to a persistent `mathql serve` process, `describe_schema`
to a one-shot `mathql describe`.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

from mcp.server.fastmcp import FastMCP

_MATHQL_DIR = Path(__file__).resolve().parent.parent / "MathQL"
_BIN = _MATHQL_DIR / ".lake" / "build" / "bin" / "mathql"

server = FastMCP("mathql")

_engine: subprocess.Popen[str] | None = None


def _serve() -> subprocess.Popen[str]:
    """The persistent `mathql serve` process, restarted if it has exited."""
    global _engine
    if _engine is None or _engine.poll() is not None:
        _engine = subprocess.Popen(
            [str(_BIN), "serve"], cwd=_MATHQL_DIR,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        )
    return _engine


@server.tool()
def query(query: str) -> Any:
    """Run a MathQL query, e.g. "{ g.num_edges | g ∈ SmallGraphs, g.is_tree }",
    and return the list of results."""
    engine = _serve()
    assert engine.stdin and engine.stdout
    engine.stdin.write(query.replace("\n", " ") + "\n")
    engine.stdin.flush()
    result = json.loads(engine.stdout.readline())
    if "error" in result:
        raise ValueError(result["error"])
    return result["ok"]


@server.tool()
def describe_schema() -> Any:
    """List the domains that can be queried and the invariants each provides."""
    completed = subprocess.run(
        [str(_BIN), "describe"], cwd=_MATHQL_DIR, capture_output=True, text=True
    )
    return json.loads(completed.stdout)


def main() -> None:
    server.run()


if __name__ == "__main__":
    main()
