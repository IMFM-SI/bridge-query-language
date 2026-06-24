"""Shared fixtures: a small in-tree graph database built from known graphs."""

from __future__ import annotations

import sqlite3

import networkx as nx
import pytest

import generate_graphs as gen
from mathql import schema
from mathql.databases.graphs import SMALL_GRAPHS

_GRAPHS = {
    "triangle": nx.complete_graph(3),
    "path3": nx.path_graph(3),
    "cycle4": nx.cycle_graph(4),
    "complete4": nx.complete_graph(4),
    "empty3": nx.empty_graph(3),
    "star3": nx.star_graph(3),
}


def _graph6(graph: nx.Graph) -> str:
    return nx.to_graph6_bytes(graph, header=False).decode("ascii").strip()


@pytest.fixture
def graphs_db(tmp_path) -> schema.Database:
    """A `SmallGraphs` database holding the six graphs in `_GRAPHS`, with
    invariants computed exactly as `generate_graphs` computes them."""
    path = tmp_path / "fixture.db"
    connection = sqlite3.connect(path)
    columns = ", ".join(f'"{name}" {sql_type}' for name, sql_type in gen.COLUMNS)
    connection.execute(f"CREATE TABLE graph (id INTEGER PRIMARY KEY, {columns})")
    insert = (
        f"INSERT INTO graph ({', '.join(name for name, _ in gen.COLUMNS)}) "
        f"VALUES ({', '.join('?' for _ in gen.COLUMNS)})"
    )
    connection.executemany(insert, [gen.row_for(_graph6(graph)) for graph in _GRAPHS.values()])
    connection.commit()
    connection.close()
    return schema.Database(path=path, domains=dict(SMALL_GRAPHS.domains))
