#!/usr/bin/env python3
"""Run a handful of MathQL queries against the small-graphs database and print
their result counts with one sample answer each.

Run from the repository root after generating `data/graphs-small.db`:

    python python/examples.py
"""

from __future__ import annotations

from mathql.databases.graphs import SMALL_GRAPHS
from mathql.engine import run

EXAMPLES = [
    ("Number of edges of each tree, by vertex count",
     "{ (g.num_vertices, g.num_edges) for g in SmallGraphs if g.is_tree }"),
    ("Chromatic numbers of the connected graphs on 5 vertices",
     "{ g.chromatic_number for g in SmallGraphs if g.num_vertices == 5 && g.is_connected }"),
    ("Non-planar graphs, by vertex count",
     "{ g.num_vertices for g in SmallGraphs if !g.is_planar }"),
    ("Regular graphs whose girth exceeds twice the chromatic number",
     "{ g for g in SmallGraphs if g.is_regular && g.girth > 2 * g.chromatic_number }"),
    ("Degree sequences of graphs whose radius is below their diameter",
     "{ g.degree_sequence for g in SmallGraphs if g.radius < g.diameter }"),
    ("Complete graphs (every vertex adjacent to all others)",
     "{ g for g in SmallGraphs if g.is_connected && g.min_degree == g.num_vertices - 1 }"),
]


def main() -> None:
    for description, query in EXAMPLES:
        results = run(query, SMALL_GRAPHS)
        sample = results[0] if results else "(none)"
        print(description)
        print(f"    {query}")
        print(f"    {len(results)} results; first: {sample}")
        print()


if __name__ == "__main__":
    main()
