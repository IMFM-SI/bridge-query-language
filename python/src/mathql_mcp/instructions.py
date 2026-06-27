"""The natural-language orientation handed to the model as the server's instructions."""

import json

SUMMARY = """## Writing queries
`query` takes: domains (e.g. [["g", "Graph"]]); output (["g.field", ...], or ["g"]
for the whole object); and optional condition, order ([expression, "asc"|"desc"]
pairs), and limit. Conditions and order expressions use fields (g.num_vertices),
literals, arithmetic (+ - *), comparisons (== != < <= > >=), booleans (&& || !),
and defined/undefined for absence; a comparison needs both sides the same scalar
type (int/bool/string). ASCII operators are preferred; ∧ ∨ ¬ ≤ ≥ ≠ also work. Call
the `grammar` tool (or read the mathql://grammar resource) for the full grammar."""

GRAPH_TOOLS = """## Inspecting a graph
A query returns a graph as its `graph6` string, which is opaque on its own. The graph
tools decode it (vertices are numbered 0..n-1):
- `edge_list` — vertex count and edges;
- `neighbors`, `shortest_path` — a vertex's neighbors, a path between two vertices;
- `max_clique`, `max_independent_set`, `connected_components` — exact witnesses for the
  clique number, independence number, and component count;
- `coloring` — a proper coloring (greedy; may exceed the chromatic number)."""


def build_instructions(schema: dict) -> str:
    """A natural-language orientation for the model, built from the schema."""
    lines = [schema.get("overview", ""), "", "## Domains and fields"]
    for domain in schema.get("domains", []):
        lines.append(f"- {domain['name']}: {domain.get('doc', '')}")
        for field in domain.get("fields", []):
            lines.append(f"    {field['label']} : {field['type']} — {field.get('doc', '')}")
    lines += ["", SUMMARY, "", GRAPH_TOOLS, "", "## Examples (call `describe` for the full list)"]
    for example in schema.get("examples", [])[:3]:
        lines.append(f"- {example['note']}: {json.dumps(example['query'])}")
    return "\n".join(lines)
