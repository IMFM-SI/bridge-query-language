"""The MathQL MCP server: wire the engine and tools into a FastMCP app.

Run via the `mathql-mcp` console script (after `pip install -e python`), or point an
MCP client at it. The repository paths below assume an editable install from the repo.
"""

from pathlib import Path

from mcp.server.fastmcp import FastMCP

from mathql_mcp import graph_tools, query_tools
from mathql_mcp.engine import Engine
from mathql_mcp.instructions import build_instructions

ROOT = Path(__file__).resolve().parents[3]
MATHQL_DIR = ROOT / "MathQL"
DB_PATH = ROOT / "data" / "graphs-small.db"
GRAMMAR_PATH = ROOT / "docs" / "query-grammar.md"


def build() -> FastMCP:
    """Build the FastMCP app, starting the engine and registering the tools."""
    engine = Engine(MATHQL_DIR, DB_PATH)
    app = FastMCP("mathql", instructions=build_instructions(engine.request({"describe": True})))
    query_tools.register(app, engine, GRAMMAR_PATH)
    graph_tools.register(app)
    return app


mcp = build()


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
