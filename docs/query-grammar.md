# MathQL query grammar

This document describes the grammar of the MathQL query language: the structure of a
query and the expressions that appear in its condition and ordering.

## The query

A query is a JSON object:

```
{
  "domains":   [[variable, domain], ...],
  "output":    [item, ...],
  "condition": "<expression>",
  "order":     [["<expression>", "asc" | "desc"], ...],
  "limit":     <integer>
}
```

- `domains` (required) binds one or more variables, each ranging over a named
  domain; several bindings form a join.
- `output` (required) lists the values to return. An item is either a variable `x`,
  which returns the whole object, or `x.field`, which returns a single field.
- `condition` (optional, default `true`) restricts the result to the objects, or
  tuples of objects, that satisfy it; it must have type `bool`.
- `order` (optional) sorts the result by one or more scalar expressions, each
  ascending or descending.
- `limit` (optional) bounds the number of rows returned.

The available domains and their fields are obtained from the `describe` tool.

## Types

Every value has a type:

```
type ::= "int"
       | "bool"
       | "string"
       | "list" type
       | type "*" … "*" type
```

- `int` — integers.
- `bool` — the truth values `true` and `false`.
- `string` — text.
- `list` τ — an ordered list of values of type τ.
- a product `τ₁ * … * τₙ` — a tuple of components of the given types; the nullary
  product is the unit type.

## Expressions

The condition and the order expressions are written in the following grammar. It is
ambiguous; precedence and associativity are fixed under *Operators* below.

```
expr ::= "if" expr "then" expr "else" expr
       | expr "||" expr
       | expr "&&" expr
       | expr "==" expr
       | expr "!=" expr
       | expr "<" expr
       | expr "<=" expr
       | expr ">" expr
       | expr ">=" expr
       | expr "::" expr
       | expr "+" expr
       | expr "-" expr
       | expr "*" expr
       | "!" expr
       | "-" expr
       | "defined" expr
       | "undefined" expr
       | expr "." integer
       | atom

atom ::= integer
       | string
       | "true"
       | "false"
       | variable "." field
       | constant
       | "(" expr ")"
       | "(" expr "," … "," expr ")"
       | "[" "]"
       | "[" expr "," … "," expr "]"
```

Each former and how it types:

- `if c then a else b` — yields `a` when `c` is true and `b` otherwise; `c` must be
  `bool`, the two branches must share a type, and that is the type of the whole
  expression.
- `e1 || e2` and `e1 && e2` — disjunction and conjunction; the operands and the
  result are `bool`.
- `e1 == e2`, `e1 != e2`, `e1 < e2`, `e1 <= e2`, `e1 > e2`, `e1 >= e2` — comparisons;
  the two operands must have the same type, and the result is `bool`.
- `e1 :: e2` — prepends `e1` to the list `e2`; with `e1` of type τ and `e2` of type
  `list` τ, the result has type `list` τ.
- `e1 + e2`, `e1 - e2`, `e1 * e2`, and `- e` — integer arithmetic; the operands and
  the result are `int`.
- `! e` — boolean negation; the operand and the result are `bool`.
- `defined e` and `undefined e` — test whether `e` has a value or is absent; the
  result is `bool`.
- `e . i` — the `i`-th component (counting from zero) of the tuple `e`; its type is
  that component's type.
- a literal `42`, `"text"`, `true`, or `false` — of type `int`, `string`, `bool`,
  `bool`.
- `x.field` — the value of the field `field` of the variable `x`, of the field's
  declared type (see `describe`).
- `c` — a named constant declared by the database, of its declared type.
- `(e)` — grouping; `(e1, …, en)` — a tuple, of the corresponding product type.
- `[]` and `[e1, …, en]` — a list literal, of type `list` τ.

A condition and an order expression are evaluated by the database, which has no
representation for lists or products; an expression of list or product type — `::`,
a list or tuple literal, or a tuple projection — therefore cannot appear in one.

## Operators

The operators are listed in order of increasing precedence; operators on the same
line share a precedence level.

- `if … then … else …`, the conditional.
- `||` (`∨`), disjunction, left-associative.
- `&&` (`∧`), conjunction, left-associative.
- `==` `!=` `<` `<=` `>` `>=`, comparison, non-associative; the equivalents `=`, `≠`,
  `≤`, `≥` are also accepted.
- `::`, list construction, right-associative.
- `+` `-`, addition and subtraction, left-associative.
- `*`, multiplication, left-associative.
- `!` (`¬`), unary `-`, `defined`, and `undefined`, the prefix operators.
- `.`, postfix projection of a tuple component by position.

The ASCII spellings are recommended; the UTF-8 forms shown in parentheses are
accepted equivalents.
