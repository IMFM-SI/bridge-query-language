"""MathQL MCP server.

Exposes the MathQL query engine (the Lean `mathql` executable) as MCP tools. The
engine is a single long-lived subprocess speaking JSON Lines over stdin/stdout:
one request object per line, one response object per line (`{"rows": ...}` or
`{"error": ...}`; a `{"describe": true}` request returns the database schema).

Run with an MCP client pointed at `python python/mathql.py`, or `mcp dev
python/mathql.py` for the inspector.
"""

import json
import subprocess
import threading
from pathlib import Path
from typing import Optional

from mcp.server.fastmcp import FastMCP

ROOT = Path(__file__).resolve().parent.parent
MATHQL_DIR = ROOT / "MathQL"
DB_PATH = ROOT / "data" / "graphs-small.db"
GRAMMAR_PATH = ROOT / "docs" / "query-grammar.md"


class Engine:
    """A persistent `mathql` subprocess, addressed one request at a time."""

    def __init__(self, mathql_dir: Path, db_path: Path) -> None:
        self.cmd = ["lake", "exe", "mathql", str(db_path)]
        self.cwd = str(mathql_dir)
        self.lock = threading.Lock()
        self.proc: Optional[subprocess.Popen] = None
        self._start()

    def _start(self) -> None:
        self.proc = subprocess.Popen(
            self.cmd, cwd=self.cwd,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            text=True, bufsize=1,
        )

    def request(self, obj: dict):
        """Send one request object and return the decoded response object."""
        with self.lock:
            if self.proc is None or self.proc.poll() is not None:
                self._start()
            assert self.proc is not None and self.proc.stdin is not None
            assert self.proc.stdout is not None
            self.proc.stdin.write(json.dumps(obj) + "\n")
            self.proc.stdin.flush()
            response = self.proc.stdout.readline()
            if not response:
                self._start()
                raise RuntimeError("mathql engine exited without responding")
            return json.loads(response)


SUMMARY = """## Writing queries
`query` takes: domains (e.g. [["g", "Graph"]]); output (["g.field", ...], or ["g"]
for the whole object); and optional condition, order ([expression, "asc"|"desc"]
pairs), and limit. Conditions and order expressions use fields (g.num_vertices),
literals, arithmetic (+ - *), comparisons (== != < <= > >=), booleans (&& || !),
and defined/undefined for absence; a comparison needs both sides the same scalar
type (int/bool/string). ASCII operators are preferred; ∧ ∨ ¬ ≤ ≥ ≠ also work. Call
the `grammar` tool (or read the mathql://grammar resource) for the full grammar."""


def read_grammar() -> str:
    return GRAMMAR_PATH.read_text()


def build_instructions(schema: dict) -> str:
    """A natural-language orientation for the model, built from the schema."""
    lines = [schema.get("overview", ""), "", "## Domains and fields"]
    for domain in schema.get("domains", []):
        lines.append(f"- {domain['name']}: {domain.get('doc', '')}")
        for field in domain.get("fields", []):
            lines.append(f"    {field['label']} : {field['type']} — {field.get('doc', '')}")
    lines += ["", SUMMARY, "", "## Examples (call `describe` for the full list)"]
    for example in schema.get("examples", [])[:3]:
        lines.append(f"- {example['note']}: {json.dumps(example['query'])}")
    return "\n".join(lines)


engine = Engine(MATHQL_DIR, DB_PATH)
mcp = FastMCP("mathql", instructions=build_instructions(engine.request({"describe": True})))


@mcp.tool()
def query(
    domains: list[list[str]],
    output: list[str],
    condition: Optional[str] = None,
    order: Optional[list[list[str]]] = None,
    limit: Optional[int] = None,
) -> list:
    """Run a MathQL query and return the matching rows.

    domains: variable bindings, e.g. [["g", "Graph"]].
    output: items to return, each "x" (the whole object) or "x.field".
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


if __name__ == "__main__":
    mcp.run()
