"""The MathQL MCP server: wire the databases and tools into a FastMCP app.

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
GRAMMAR_PATH = ROOT / "docs" / "query-grammar.md"

DATABASES = [
    ("graphs-small", ROOT / "data" / "graphs-small.db"),
    ("sym-ob-small", ROOT / "data" / "sym-ob-small.db"),
]


def build() -> FastMCP:
    """Build the FastMCP app: one subprocess per available database, tools registered."""
    engines = {
        name: Engine(MATHQL_DIR, name, path) for name, path in DATABASES if path.exists()
    }
    schemas = {name: engine.request({"describe": True}) for name, engine in engines.items()}
    app = FastMCP("mathql", instructions=build_instructions(schemas))
    query_tools.register(app, engines, schemas, GRAMMAR_PATH)
    graph_tools.register(app)
    return app


mcp = build()


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
