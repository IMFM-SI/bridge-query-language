from __future__ import annotations

from mathql import syntax
from mathql.compiler import compile_condition, evaluate
from mathql.databases.graphs import SMALL_GRAPHS
from mathql.parser import parse

_DOMAIN = SMALL_GRAPHS.domains["SmallGraphs"]


def _condition(text: str) -> syntax.Expression:
    return parse(text).condition


def test_translates_full_condition_to_sql():
    where, params, residual = compile_condition(
        _condition("{ g for g in D if g.num_vertices == 5 && g.is_connected }"), _DOMAIN
    )
    assert where == "(num_vertices = ?) AND is_connected"
    assert params == [5]
    assert residual is None


def test_untranslatable_conjunct_becomes_residual():
    where, params, residual = compile_condition(
        _condition("{ g for g in D if g.is_tree && g }"), _DOMAIN
    )
    assert where == "is_tree"
    assert residual == syntax.Variable("g")


def test_evaluate_arithmetic():
    expr = syntax.BinaryOp("+", syntax.Attribute(syntax.Variable("g"), "num_edges"), syntax.Literal(1))
    assert evaluate(expr, {"num_edges": 3}, _DOMAIN) == 4


def test_comparison_with_missing_value_is_false():
    expr = _condition("{ g for g in D if g.radius < g.diameter }")
    assert evaluate(expr, {"radius": 1, "diameter": None}, _DOMAIN) is False
