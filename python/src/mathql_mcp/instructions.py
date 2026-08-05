"""The natural-language orientation handed to the model as the server's instructions."""

import json
from typing import Any

SUMMARY = """## Writing queries
`query` takes: domains (e.g. [["g", "Graph"]]); output, a mapping from each result
column name to the expression it returns (e.g. {"g6": "id(g)", "edges":
"g.num_edges"}); and optional condition, order ([expression, "asc"|"desc"] pairs,
which may refer to the output column names), limit, and database. Expressions use
fields (g.num_vertices), id(x) for an object's primary key, literals, arithmetic
(+ - *), comparisons (== != < <= > >=), booleans (&& || !), and defined/undefined
for absence; a comparison needs both sides the same type. String literals are
single-quoted ('text', a literal quote doubled as ''). ASCII operators are
preferred; ∧ ∨ ¬ ≤ ≥ ≠ also work. Call the `grammar` tool (or read the
mathql://grammar resource) for the full grammar."""

GRAPH_TOOLS = """## Inspecting a graph
A query returns a graph as its `graph6` string, which is opaque on its own. The graph
tools decode it (vertices are numbered 0..n-1):
- `edge_list` — vertex count and edges;
- `neighbors`, `shortest_path` — a vertex's neighbors, a path between two vertices;
- `max_clique`, `max_independent_set`, `connected_components` — exact witnesses for the
  clique number, independence number, and component count;
- `coloring` — a proper coloring (greedy; may exceed the chromatic number)."""


def _database_section(name: str, schema: dict[str, Any]) -> list[str]:
    """The instruction lines for one database: overview, domains, two examples."""
    lines = [f"## Database `{name}`", schema.get("overview", ""), "", "### Domains and fields"]
    for domain in schema.get("domains", []):
        lines.append(f"- {domain['name']}: {domain.get('doc', '')}")
        input_fields = domain.get("inputFields", [])
        if input_fields:
            lines.append("  Input fields — scalar values, written `x.field`:")
            for field in input_fields:
                lines.append(f"    {field['label']} : {field['type']} — {field.get('doc', '')}")
        domain_fields = domain.get("domainFields", [])
        if domain_fields:
            lines.append("  Domain fields — links to another object, written `x.field`, "
                         "yielding an object you can project or take id() of:")
            for field in domain_fields:
                lines.append(f"    {field['label']} → {field['domain']} — {field.get('doc', '')}")
    lines += ["", "### Examples (call `describe` for the full list)"]
    for example in schema.get("examples", [])[:2]:
        lines.append(f"- {example['note']}: {json.dumps(example['query'])}")
    return lines


def build_instructions(schemas: dict[str, dict[str, Any]]) -> str:
    """A natural-language orientation for the model, built from the databases' schemas."""
    default = next(iter(schemas), "")
    lines = [
        (
            f"Databases served: {', '.join(schemas)}. `query` and `describe` take a "
            f"`database` parameter selecting one (default: {default}); `describe` with "
            "no arguments lists them."
        ),
        "",
    ]
    for name, schema in schemas.items():
        lines += _database_section(name, schema) + [""]
    lines += [SUMMARY, "", GRAPH_TOOLS]
    return "\n".join(lines)
