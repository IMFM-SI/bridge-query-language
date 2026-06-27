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

## Expressions

The condition and the order expressions are written in the following grammar.

```
expr     ::= "if" expr "then" expr "else" expr
           | cons
cons     ::= or ("::" cons)?
or       ::= and ("||" and)*
and      ::= cmp ("&&" cmp)*
cmp      ::= add (compare add)?
add      ::= mul (("+" | "-") mul)*
mul      ::= unary ("*" unary)*
unary    ::= ("defined" | "undefined" | "!" | "-") unary
           | postfix
postfix  ::= atom ("." integer)*
atom     ::= integer | "true" | "false" | string
           | "[" (expr ("," expr)*)? "]"
           | "(" expr ("," expr)* ")"
           | variable "." field
           | constant
compare  ::= "==" | "=" | "!=" | "<" | "<=" | ">" | ">="
```

## Operators

The operators are listed in order of increasing precedence; operators on the same
line share a precedence level.

- `if … then … else …`, the conditional.
- `::`, list construction, right-associative.
- `||` (`∨`), disjunction, left-associative.
- `&&` (`∧`), conjunction, left-associative.
- `==` `!=` `<` `<=` `>` `>=`, comparison, non-associative; the equivalents `=`, `≠`,
  `≤`, `≥` are also accepted.
- `+` `-`, addition and subtraction, left-associative.
- `*`, multiplication, left-associative.
- `!` (`¬`), unary `-`, `defined`, and `undefined`, the prefix operators.
- `.`, postfix projection of a tuple component by position.

The ASCII spellings are recommended; the UTF-8 forms shown in parentheses are
accepted equivalents.

## Types

The scalar types are `int`, `bool`, and `string`. A comparison requires both
operands to have the same type and yields `bool`; arithmetic operates on `int`; and
`&&`, `||`, `!` operate on `bool`. The presence tests `defined e` and `undefined e`
yield `bool`.

A condition and every order expression are evaluated by the database, so they are
restricted to field projections, constants, literals, arithmetic, comparison,
`&&`/`||`/`!`, the conditional, and `defined`/`undefined`. List and tuple
expressions, and tuple projection, belong to the language but are unavailable in a
query, because the database has no representation for them.

## Examples

```
{"domains": [["g", "Graph"]], "output": ["g.graph6"], "condition": "g.num_vertices == 5 && g.is_tree"}
{"domains": [["g", "Graph"]], "output": ["g.graph6", "g.num_edges"], "condition": "g.num_vertices == 5", "order": [["g.num_edges", "desc"]], "limit": 3}
{"domains": [["g", "Graph"], ["h", "Graph"]], "output": ["g.graph6", "h.graph6"], "condition": "g.num_vertices == h.num_vertices && g.num_edges < h.num_edges", "limit": 5}
{"domains": [["g", "Graph"]], "output": ["g"], "condition": "undefined g.girth && g.num_vertices <= 4"}
```
