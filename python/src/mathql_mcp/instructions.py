"""The natural-language orientation handed to the model as the server's instructions."""

import json
from typing import Any

SUMMARY = """## Writing queries
`query` takes: domains (e.g. [["g", "Graph"]]); output, an ordered list of
[column name, expression] pairs (e.g. [["g6", "id(g)"], ["edges", "g.num_edges"]])
whose order is the column order of every row; and optional condition, order
([expression, "asc"|"desc"] pairs, which may refer to the output column names),
limit, postprocess, and database.

Expressions are built from fields (g.num_vertices), id(x) for an object's primary
key, literals, arithmetic (+ - *), comparisons (== != < <= > >=), booleans (&& || !),
defined/undefined for absence, tuples ((a, b, c)) with e.i selecting the i-th
component counting from zero, lists ([a, b]), if c then a else b, and f(x) for a
function the database declares.
A comparison requires both sides to have the same type. String literals are
single-quoted ('text', a literal quote doubled as ''). ASCII operators are preferred;
∧ ∨ ¬ ≤ ≥ ≠ are accepted equivalents.

postprocess is an ordered list of [column name, expression] pairs appended to each
row, evaluated outside the database after it returns the rows; each expression may
refer to the output columns and to the entries preceding it. Each returned row is a
list of [name, value] pairs, the output columns first and then the postprocess
columns; an absent value is null.

Call the `grammar` tool (or read the mathql://grammar resource) for the complete
grammar."""

GRAPH_TOOLS = """## Inspecting a graph
A query returns a graph as its `graph6` string. The graph tools decode it
(vertices are numbered 0..n-1):
- `edge_list` — vertex count and edges;
- `neighbors`, `shortest_path` — a vertex's neighbors, a path between two vertices;
- `max_clique`, `max_independent_set`, `connected_components` — exact witnesses for the
  clique number, independence number, and component count;
- `coloring` — a proper coloring (greedy; the color count may exceed the chromatic
  number)."""


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
            "an empty argument list returns them."
        ),
        "",
    ]
    for name, schema in schemas.items():
        lines += _database_section(name, schema) + [""]
    lines += [SUMMARY, "", GRAPH_TOOLS]
    return "\n".join(lines)
