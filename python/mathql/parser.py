"""Parsing of MathQL concrete syntax into the abstract syntax of `syntax`."""

from __future__ import annotations

from typing import cast

from lark import Lark, Transformer, v_args

from mathql import syntax

_GRAMMAR = r"""
    query: "{" expression "for" CNAME "in" CNAME ["if" expression] "}"

    ?expression: or_expr
    ?or_expr:  or_expr OR and_expr     -> binary
            |  and_expr
    ?and_expr: and_expr AND comparison -> binary
            |  comparison
    ?comparison: additive (COMPARE additive)?  -> compare
    ?additive: additive ADD multiplicative -> binary
            |  multiplicative
    ?multiplicative: multiplicative MUL unary -> binary
            |  unary
    ?unary: PREFIX unary -> unary
         |  postfix
    ?postfix: postfix "." CNAME -> attribute
           |  atom
    ?atom: INT            -> integer
         | "true"         -> true
         | "false"        -> false
         | ESCAPED_STRING  -> string
         | CNAME          -> variable
         | "(" expression ")"
         | "(" expression ("," expression)+ ")" -> tuple

    OR: "||"
    AND: "&&"
    COMPARE: "==" | "!=" | "<=" | ">=" | "<" | ">"
    ADD: "+" | "-"
    MUL: "*"
    PREFIX: "!" | "-"

    %import common.CNAME
    %import common.INT
    %import common.ESCAPED_STRING
    %import common.WS
    %ignore WS
"""


@v_args(inline=True)
class _ToSyntax(Transformer):
    """Turns a Lark parse tree into `syntax` nodes."""

    def query(self, result, variable, domain, condition):
        return syntax.Query(result, str(variable), str(domain), condition)

    def binary(self, left, op, right):
        return syntax.BinaryOp(str(op), left, right)

    def compare(self, left, op=None, right=None):
        return left if op is None else syntax.BinaryOp(str(op), left, right)

    def unary(self, op, operand):
        return syntax.UnaryOp(str(op), operand)

    def attribute(self, obj, name):
        return syntax.Attribute(obj, str(name))

    def tuple(self, *items):
        return syntax.TupleExpr(tuple(items))

    def variable(self, name):
        return syntax.Variable(str(name))

    def integer(self, token):
        return syntax.Literal(int(token))

    def string(self, token):
        return syntax.Literal(str(token)[1:-1])

    def true(self):
        return syntax.Literal(True)

    def false(self):
        return syntax.Literal(False)


_PARSER = Lark(_GRAMMAR, start="query", parser="lalr", transformer=_ToSyntax())


def parse(text: str) -> syntax.Query:
    """Parse a MathQL query. Raises `lark.exceptions.LarkError` on malformed input."""
    return cast(syntax.Query, _PARSER.parse(text))
