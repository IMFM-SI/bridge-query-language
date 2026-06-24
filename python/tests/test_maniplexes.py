from __future__ import annotations

from mathql.engine import run


def test_returns_every_maniplex(maniplexes_db):
    assert len(run("{ m for m in Maniplexes }", maniplexes_db)) == 3


def test_counts_orientable(maniplexes_db):
    assert len(run("{ m for m in Maniplexes if m.orientable }", maniplexes_db)) == 2


def test_filters_on_string_attribute(maniplexes_db):
    assert run('{ m.size for m in Maniplexes if m.polytopality == "Polytopal" }', maniplexes_db) == [8]


def test_schlafli_symbol_decoded_as_list(maniplexes_db):
    assert run("{ m.schlafli_symbol for m in Maniplexes if m.size == 16 }", maniplexes_db) == [[4, 4, 2]]


def test_numeric_comparison(maniplexes_db):
    assert sorted(run("{ m.size for m in Maniplexes if m.size < 20 }", maniplexes_db)) == [8, 16]
