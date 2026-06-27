# The MathQL language

MathQL is a small typed language for querying databases of mathematical objects. A
query names one or more domains of objects, a condition they must satisfy, and what
to return. This document describes the types, the expression language and its
bidirectional typing, the shape of a query, and how a query is realized against a
concrete database. It tracks the Lean implementation under `MathQL/`. The concrete
syntax and operator precedence of expressions are in
[`docs/query-grammar.md`](docs/query-grammar.md).

## Design goals

- **The condition reads as ordinary mathematics.** The expression language uses the
  familiar operators, so `g.is_planar && g.girth > 4` reads directly.
- **The design follows standard programming-language theory** — an intrinsically
  typed term language with a bidirectional typing judgement.
- A query is consumed programmatically (e.g. over the MCP interface), so it is
  submitted as a **JSON object** whose fields are the parts of a set-builder
  comprehension — the domains, the output, the condition — with the expressions
  inside written in the notation below.

## Types

```
τ ::= Int | Bool | String        scalar (base) types
    | List τ                     list (ordered)
    | τ₁ × ⋯ × τₙ                 product (n = 0 is the unit type)
```

There is no option type, and there are no named record or enumeration *types*: a
type is a finite tree over scalars, lists, and products. Domains are named — they
are what a variable ranges over — and a database may declare named *constants*, but
neither is a type in this grammar.

`Int`, `Bool`, and `String` are the scalar types, stored as ordinary columns. `List τ`
and products are realized as JSON arrays (see *Realization*), so they too may appear in
a query.

## Expressions

An expression denotes a value computed from the bound objects. A variable is not an
expression by itself; a variable `x` appears only in a field projection `x.ℓ`.

```
e ::= n | "s" | true | false                          -- literals
    | x.ℓ                                              -- field projection
    | c                                                -- a named constant
    | - e | e + e | e - e | e * e                      -- arithmetic (Int)
    | ¬ e | e ∧ e | e ∨ e                              -- logic (Bool)
    | e = e | e ≠ e | e < e | e ≤ e | e > e | e ≥ e    -- comparison
    | if e then e else e                               -- conditional
    | defined e | undefined e                          -- presence tests
    | (e₁, …, eₙ) | e.i                                 -- product and projection
    | [] | [e₁, …, eₙ]                                  -- list
```

ASCII synonyms: `∧`=`&&`, `∨`=`||`, `¬`=`!`, `≤`=`<=`, `≥`=`>=`, `≠`=`!=`, `=`=`==`.

## Typing

The judgement is bidirectional: synthesis `Γ ⊢ e ⇒ τ` computes a type, checking
`Γ ⊢ e ⇐ τ` checks against a given one. The context `Γ` records the bound variables
(each with its domain) and the database's constants. `Typing.lean` implements both
modes against the declarative rules in `Rules.lean`:

- **literals** — `n ⇒ Int`, `"s" ⇒ String`, `true`/`false ⇒ Bool`.
- **field** — if `ℓ` is a field of `x`'s domain with type `τ`, then `x.ℓ ⇒ τ`.
- **constant** — if the database declares `c : τ`, then `c ⇒ τ`.
- **arithmetic** — `- e ⇒ Int` with `e ⇐ Int`; `e₁ ⊙ e₂ ⇒ Int` for `⊙ ∈ {+,-,*}`,
  both `⇐ Int`.
- **logic** — `¬ e ⇒ Bool` with `e ⇐ Bool`; `e₁ ⊙ e₂ ⇒ Bool` for `⊙ ∈ {∧,∨}`, both
  `⇐ Bool`.
- **comparison** — `e₁ ⊙ e₂ ⇒ Bool` when `e₁ ⇒ τ` and `e₂ ⇐ τ`, the same `τ` on both
  sides, for every comparison `⊙` (`= ≠ < ≤ > ≥`).
- **conditional** — `if b then e₁ else e₂ : τ` with `b ⇐ Bool` and both branches at
  `τ`.
- **presence** — `defined e ⇒ Bool` and `undefined e ⇒ Bool` for any `e ⇒ τ`.
- **product** — `(e₁, …, eₙ) ⇒ τ₁ × ⋯ × τₙ`; `e.i ⇒ τᵢ` when `e ⇒ τ₁ × ⋯ × τₙ`.
- **list** — a list literal `[e₁, …, eₙ]` has type `List τ` when every `eᵢ` has type
  `τ`; `[]` checks against any `List τ`.

All six comparisons share one rule: both sides at a single type, result `Bool`. This
holds at every type — scalars, lists, and products — because lists and products are
realized as JSON arrays, and a comparison of them is SQLite's comparison over those
arrays.

## Queries

A query is the top-level form, submitted as JSON:

```
{ "domains":   [[x, D], …],          (required)
  "output":    [item, …],            (required)
  "condition": e,                    (optional, default true)
  "order":     [[e, dir], …],        (optional; dir is "asc" or "desc")
  "limit":     n }                   (optional)
```

- `domains` binds variables `x₁ ∈ D₁, …`; with more than one binding the query
  ranges over the product of the domains (a join).
- `output` lists what to return; an item is a variable `x` (the whole object) or a
  field projection `x.ℓ`.
- `condition` is an expression of type `Bool` over the bound variables.
- `order` sorts by expressions, each ascending or descending; an order expression
  must be a scalar.
- `limit` caps the number of rows.

A query returns a list of rows — one per combination of objects satisfying the
condition, in the requested order, capped by `limit`. Each row is a JSON object
keyed by the output items.

## Absence

A possibly-absent invariant keeps its scalar type — `diameter : Int` — and may be
absent for a given object (a `NULL` column). There is no option type and no `match`;
absence is observed only through `defined e` and `undefined e`, which compile to SQL
`IS NOT NULL` / `IS NULL`. A comparison against an absent value is neither true nor
false (SQL's three-valued logic), so such a row is dropped from the result.

## Realization

A database connects the language to storage. It maps:

- a **domain** → a table or view;
- a **field** → a column, with a codec decoding the cell into the field's value
  (e.g. JSON text → `List Int`);
- a **constant** → a fixed SQL expression;
- a query's **condition** → a SQL `WHERE`; its **output** → selected columns,
  decoded and rendered to JSON (a whole-object item renders all of the domain's
  output fields); its **order** → `ORDER BY`; its **limit** → `LIMIT`.

Lists and products are realized as JSON arrays: a list or tuple literal compiles to
`json_array(…)`, a tuple projection to `json_extract(…)`, and a comparison of lists or
tuples is SQLite's comparison over the (canonical) JSON. Ordering keys must still be
scalar.

## Implementation

MathQL is a standalone Lean package. Expressions are parsed by a parser combinator
(`Parsing.lean`); a whole query is decoded from JSON (`QueryJson.lean`); it is
elaborated by the bidirectional judgement into an intrinsically-typed `Expr`
(`Rules.lean`, `Typing.lean`), so ill-typed queries are rejected with located
errors; and it is compiled to a single SQL `SELECT` (`Compile.lean`, `SQL.lean`).
The result rows are decoded by the realization's codecs into JSON (`Execute.lean`).
Every construct that reaches the database has a SQL image; there is no separate
evaluator.
