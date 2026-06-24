from __future__ import annotations

from mathql.engine import run


def test_returns_every_object_without_condition(graphs_db):
    assert len(run("{ g for g in SmallGraphs }", graphs_db)) == 6


def test_counts_trees(graphs_db):
    # Among the fixture graphs, path3 and star3 are trees.
    trees = run("{ g.num_vertices for g in SmallGraphs if g.is_tree }", graphs_db)
    assert sorted(trees) == [3, 4]


def test_counts_regular_graphs(graphs_db):
    # triangle, cycle4, complete4, and empty3 are regular.
    assert len(run("{ g for g in SmallGraphs if g.is_regular }", graphs_db)) == 4


def test_invariant_to_invariant_comparison(graphs_db):
    # radius < diameter holds for path3 (1 < 2) and star3 (1 < 2);
    # disconnected empty3 has neither radius nor diameter.
    result = run("{ g.num_vertices for g in SmallGraphs if g.radius < g.diameter }", graphs_db)
    assert sorted(result) == [3, 4]


def test_returns_rendered_object(graphs_db):
    result = run("{ g for g in SmallGraphs if g.num_vertices == 3 && g.num_edges == 3 }", graphs_db)
    assert len(result) == 1
    assert result[0]["num_vertices"] == 3
    assert result[0]["edges"] == [[0, 1], [0, 2], [1, 2]]
    assert isinstance(result[0]["graph6"], str)


def test_tuple_projection(graphs_db):
    result = run("{ (g.num_vertices, g.num_edges) for g in SmallGraphs if g.is_tree }", graphs_db)
    assert sorted(result) == [(3, 2), (4, 3)]
