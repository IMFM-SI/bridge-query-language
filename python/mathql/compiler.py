"""Compilation and evaluation of query expressions.

`compile_condition` translates the part of a condition it can into a SQL
`WHERE` clause and returns the untranslatable remainder as a *residual*
expression. `evaluate` computes any expression — the residual, or the value a
query returns — against one decoded row.
"""

from __future__ import annotations

import operator
from collections.abc import Mapping
from typing import Any

from mathql import schema, syntax


class NotTranslatable(Exception):
    """Raised when an expression has no SQL translation and must run in Python."""


_SQL_BINARY = {
    "&&": "AND", "||": "OR",
    "==": "=", "!=": "<>", "<": "<", "<=": "<=", ">": ">", ">=": ">=",
    "+": "+", "-": "-", "*": "*",
}

_SQL_UNARY = {"!": "NOT", "-": "-"}


def _to_sql(expr: syntax.Expression, domain: schema.Domain) -> tuple[str, list[object]]:
    match expr:
        case syntax.Literal(value):
            return "?", [value]
        case syntax.Attribute(syntax.Variable(), name) if name in domain.attributes:
            return domain.attributes[name].column, []
        case syntax.UnaryOp(op, operand):
            sql, params = _to_sql(operand, domain)
            return f"({_SQL_UNARY[op]} {sql})", params
        case syntax.BinaryOp(op, left, right):
            left_sql, left_params = _to_sql(left, domain)
            right_sql, right_params = _to_sql(right, domain)
            return f"({left_sql} {_SQL_BINARY[op]} {right_sql})", left_params + right_params
        case _:
            raise NotTranslatable


def _conjuncts(expr: syntax.Expression) -> list[syntax.Expression]:
    match expr:
        case syntax.BinaryOp("&&", left, right):
            return _conjuncts(left) + _conjuncts(right)
        case _:
            return [expr]


def compile_condition(
    condition: syntax.Expression | None, domain: schema.Domain
) -> tuple[str, list[object], syntax.Expression | None]:
    """Compile a condition into a SQL `WHERE` body, its parameters, and a
    residual expression (or `None`) to evaluate in Python over fetched rows.

    Each top-level conjunct is translated independently; a conjunct without a
    SQL translation joins the residual, and the SQL keeps the rest. With no
    condition the body is `"1"`."""
    translated, params, residual = [], [], []
    for conjunct in _conjuncts(condition) if condition is not None else []:
        try:
            sql, conjunct_params = _to_sql(conjunct, domain)
        except NotTranslatable:
            residual.append(conjunct)
        else:
            translated.append(sql)
            params += conjunct_params
    where = " AND ".join(translated) if translated else "1"
    remainder: syntax.Expression | None = None
    for conjunct in residual:
        remainder = conjunct if remainder is None else syntax.BinaryOp("&&", remainder, conjunct)
    return where, params, remainder


_EVAL_BINARY = {
    "==": operator.eq, "!=": operator.ne,
    "<": operator.lt, "<=": operator.le, ">": operator.gt, ">=": operator.ge,
    "+": operator.add, "-": operator.sub, "*": operator.mul,
}


def _apply_binary(op: str, left: Any, right: Any) -> Any:
    if op == "&&":
        return bool(left) and bool(right)
    if op == "||":
        return bool(left) or bool(right)
    if left is None or right is None:
        return None if op in {"+", "-", "*"} else False
    return _EVAL_BINARY[op](left, right)


def evaluate(expr: syntax.Expression, row: Mapping[str, object], domain: schema.Domain) -> Any:
    """Compute the value of `expr` over one decoded row. A bare variable renders
    the object via the domain; a missing invariant is `None`, and comparisons
    against it yield `False`."""
    match expr:
        case syntax.Literal(value):
            return value
        case syntax.Variable():
            return domain.represent(row)
        case syntax.Attribute(syntax.Variable(), name):
            return row.get(name)
        case syntax.TupleExpr(items):
            return tuple(evaluate(item, row, domain) for item in items)
        case syntax.UnaryOp("!", operand):
            return not bool(evaluate(operand, row, domain))
        case syntax.UnaryOp("-", operand):
            number = evaluate(operand, row, domain)
            return None if number is None else -number
        case syntax.BinaryOp(op, left, right):
            return _apply_binary(op, evaluate(left, row, domain), evaluate(right, row, domain))
        case _:
            raise NotImplementedError(f"cannot evaluate {expr!r}")
