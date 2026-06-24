"""Abstract syntax of MathQL queries.

A query is a comprehension `{ result for v in Domain if condition }`. The
result and the condition are expressions built from the comprehension
variable, its attributes, literals, and operators.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Literal:
    """An integer, boolean, or string constant."""

    value: int | bool | str


@dataclass(frozen=True)
class Variable:
    """The object bound by the comprehension, e.g. `g`."""

    name: str


@dataclass(frozen=True)
class Attribute:
    """An invariant of an object, e.g. `g.chromatic_number`."""

    obj: Expression
    name: str


@dataclass(frozen=True)
class UnaryOp:
    """A prefix operator application; `op` is one of `!`, `-`."""

    op: str
    operand: Expression


@dataclass(frozen=True)
class BinaryOp:
    """An infix operator application; `op` is one of `|| && == != < <= > >= + - *`."""

    op: str
    left: Expression
    right: Expression


@dataclass(frozen=True)
class TupleExpr:
    """A tuple of expressions, e.g. `(g.num_vertices, g.num_edges)`."""

    items: tuple[Expression, ...]


Expression = Literal | Variable | Attribute | UnaryOp | BinaryOp | TupleExpr


@dataclass(frozen=True)
class Query:
    """A comprehension: return `result` for each object of `domain` bound to
    `variable` that satisfies `condition` (or every object when `condition` is
    `None`)."""

    result: Expression
    variable: str
    domain: str
    condition: Expression | None
