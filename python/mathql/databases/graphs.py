"""The `SmallGraphs` domain: all graphs on up to 8 vertices, backed by
`data/graphs-small.db` (see `generate_graphs.py`)."""

from __future__ import annotations

from collections.abc import Mapping
from pathlib import Path

import networkx as nx

from mathql import codecs, schema

_DB_PATH = Path(__file__).resolve().parents[3] / "data" / "graphs-small.db"

_INTEGER = ("num_vertices", "num_edges", "min_degree", "max_degree",
            "num_components", "num_triangles", "clique_number",
            "independence_number", "chromatic_number", "automorphism_count")
_BOOLEAN = ("is_regular", "is_connected", "is_tree", "is_forest",
            "is_bipartite", "is_planar", "is_eulerian")
_OPTIONAL_INTEGER = ("diameter", "radius", "girth")


def _attributes() -> dict[str, schema.Attribute]:
    attributes = {
        name: schema.Attribute(column=name, decode=codecs.identity, kind="integer")
        for name in _INTEGER
    }
    attributes.update(
        (name, schema.Attribute(column=name, decode=codecs.boolean, kind="boolean"))
        for name in _BOOLEAN
    )
    attributes.update(
        (name, schema.Attribute(column=name, decode=codecs.optional_int, kind="integer or null"))
        for name in _OPTIONAL_INTEGER
    )
    attributes["graph6"] = schema.Attribute(column="graph6", decode=codecs.identity, kind="string")
    attributes["degree_sequence"] = schema.Attribute(
        column="degree_sequence", decode=codecs.json_value, kind="list of integers"
    )
    return attributes


def _represent(row: Mapping[str, object]) -> object:
    """Render a graph as its graph6 code and sorted edge list."""
    graph = nx.from_graph6_bytes(str(row["graph6"]).encode("ascii"))
    return {
        "graph6": row["graph6"],
        "num_vertices": graph.number_of_nodes(),
        "edges": sorted([u, v] for u, v in (sorted(edge) for edge in graph.edges())),
    }


SMALL_GRAPHS = schema.Database(
    path=_DB_PATH,
    domains={
        "SmallGraphs": schema.Domain(
            table="graph",
            attributes=_attributes(),
            represent=_represent,
        )
    },
)
