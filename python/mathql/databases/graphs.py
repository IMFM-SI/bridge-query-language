"""The `SmallGraphs` domain: all graphs on up to 8 vertices, backed by
`data/graphs-small.db` (see `generate_graphs.py`)."""

from __future__ import annotations

import json
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Any

import networkx as nx

from mathql import schema

_DB_PATH = Path(__file__).resolve().parents[3] / "data" / "graphs-small.db"


def _identity(value: Any) -> object:
    return value


def _boolean(value: Any) -> object:
    return bool(value)


def _optional_int(value: Any) -> object:
    return None if value is None else int(value)


def _json_value(value: Any) -> object:
    return json.loads(value)


_INTEGER = ("num_vertices", "num_edges", "min_degree", "max_degree",
            "num_components", "num_triangles", "clique_number",
            "independence_number", "chromatic_number", "automorphism_count")
_BOOLEAN = ("is_regular", "is_connected", "is_tree", "is_forest",
            "is_bipartite", "is_planar", "is_eulerian")
_OPTIONAL_INTEGER = ("diameter", "radius", "girth")


def _attributes() -> dict[str, schema.Attribute]:
    by_decoder: list[tuple[tuple[str, ...], Callable[[Any], object]]] = [
        (_INTEGER, _identity),
        (_BOOLEAN, _boolean),
        (_OPTIONAL_INTEGER, _optional_int),
    ]
    attributes = {
        name: schema.Attribute(column=name, decode=decode)
        for names, decode in by_decoder
        for name in names
    }
    attributes["graph6"] = schema.Attribute(column="graph6", decode=_identity)
    attributes["degree_sequence"] = schema.Attribute(column="degree_sequence", decode=_json_value)
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
