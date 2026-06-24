from __future__ import annotations

from mathql import syntax
from mathql.parser import parse


def test_attribute_result_and_condition():
    query = parse("{ g.chromatic_number for g in SmallGraphs if g.is_connected }")
    assert query == syntax.Query(
        result=syntax.Attribute(syntax.Variable("g"), "chromatic_number"),
        variable="g",
        domain="SmallGraphs",
        condition=syntax.Attribute(syntax.Variable("g"), "is_connected"),
    )


def test_missing_condition_is_none():
    assert parse("{ g for g in SmallGraphs }").condition is None


def test_tuple_result():
    query = parse("{ (g.num_vertices, g.num_edges) for g in D }")
    assert query.result == syntax.TupleExpr(
        (syntax.Attribute(syntax.Variable("g"), "num_vertices"),
         syntax.Attribute(syntax.Variable("g"), "num_edges"))
    )


def test_arithmetic_binds_tighter_than_comparison():
    query = parse("{ g for g in D if g.girth > 2 * g.chromatic_number }")
    assert query.condition == syntax.BinaryOp(
        ">",
        syntax.Attribute(syntax.Variable("g"), "girth"),
        syntax.BinaryOp("*", syntax.Literal(2), syntax.Attribute(syntax.Variable("g"), "chromatic_number")),
    )


def test_negation_and_disjunction():
    query = parse("{ g for g in D if !g.is_planar || g.num_edges == 0 }")
    assert query.condition == syntax.BinaryOp(
        "||",
        syntax.UnaryOp("!", syntax.Attribute(syntax.Variable("g"), "is_planar")),
        syntax.BinaryOp("==", syntax.Attribute(syntax.Variable("g"), "num_edges"), syntax.Literal(0)),
    )
