# MathQL query grammar

A query is a JSON object. Conditions and order keys are written in the small
expression language below. This document is the grammar the MCP server serves to
an agent; it tracks `MathQL/MathQL/Parsing.lean`.

## Query (JSON)

```
{
  "domains":   [[variable, domain], ...],          // required; e.g. [["g", "Graph"]]
  "output":    [item, ...],                         // required; item = "x" or "x.field"
  "condition": "<expression>",                      // optional; defaults to true
  "order":     [["<expression>", "asc"|"desc"], ...], // optional
  "limit":     <integer>                            // optional
}
```

- `domains` binds one or more variables, each ranging over a named domain. Several
  bindings form a join.
- `output` lists what to return. `"x"` returns the whole object of variable `x`;
  `"x.field"` returns one field.
- `condition` keeps only the objects (or tuples of objects, for a join) satisfying
  it. It must have type `bool`.
- `order` sorts by one or more expressions, each ascending or descending. Every
  order expression must be a scalar (`int`, `bool`, or `string`).
- `limit` caps the number of returned rows.

Use the `describe` tool to learn the available domains and their fields.

## Expressions

```
expr     ::= "if" expr "then" expr "else" expr
           | cons
cons     ::= or ("::" cons)?                 -- list cons (right-assoc)
or       ::= and ("||" and)*                 -- left-assoc
and      ::= cmp ("&&" cmp)*                 -- left-assoc
cmp      ::= add (compare add)?              -- non-associative
add      ::= mul (("+" | "-") mul)*          -- left-assoc
mul      ::= unary ("*" unary)*              -- left-assoc
unary    ::= ("defined" | "undefined" | "!" | "-") unary
           | postfix
postfix  ::= atom ("." integer)*            -- tuple projection by position
atom     ::= integer | "true" | "false" | string
           | "[" (expr ("," expr)*)? "]"     -- list
           | "(" expr ("," expr)* ")"        -- parenthesized expr, or a tuple
           | variable "." field              -- field access
           | constant                        -- a bare identifier
compare  ::= "==" | "=" | "!=" | "<" | "<=" | ">" | ">="
```

Precedence, loosest to tightest:

```
if/then/else  <  ::  <  ||  <  &&  <  comparison  <  + -  <  *  <  unary  <  .  <  atom
```

`||`, `&&`, `+`, `-`, `*` are left-associative; `::` is right-associative; a
comparison takes exactly two operands (it does not chain).

## Operators

| meaning | ASCII | UTF-8 |
| --- | --- | --- |
| and | `&&` | `∧` |
| or | `\|\|` | `∨` |
| not | `!` | `¬` |
| equal | `==` (or `=`) | |
| not equal | `!=` | `≠` |
| ≤ / ≥ | `<=` / `>=` | `≤` / `≥` |
| < / > | `<` / `>` | |

ASCII is recommended; the UTF-8 forms are accepted equivalents.

## Types and what compiles

The scalar types are `int`, `bool`, `string`. A comparison requires both sides to
have the **same scalar type** and yields `bool`; arithmetic (`+ - *`, unary `-`) is
on `int`; `&& || !` are on `bool`. `defined e` / `undefined e` test whether `e` is
present (a value or absent), yielding `bool`.

`condition` and each `order` expression compile to SQL, so they are built from:
field access, constants, `int`/`string`/`bool` literals, arithmetic, comparisons,
`&& || !`, `if/then/else`, and `defined`/`undefined`. List and tuple expressions
(and tuple projection) have no SQL form and may not appear there.

## Examples

```
{"domains": [["g","Graph"]], "output": ["g.graph6"], "condition": "g.num_vertices == 5 && g.is_tree"}
{"domains": [["g","Graph"]], "output": ["g.graph6","g.num_edges"], "condition": "g.num_vertices == 5", "order": [["g.num_edges","desc"]], "limit": 3}
{"domains": [["g","Graph"],["h","Graph"]], "output": ["g.graph6","h.graph6"], "condition": "g.num_vertices == h.num_vertices && g.num_edges < h.num_edges", "limit": 5}
{"domains": [["g","Graph"]], "output": ["g"], "condition": "undefined g.girth && g.num_vertices <= 4"}
```
