# Handoff

Branch `mathql-lean`. The library builds green (`lake build`). MathQL is a
**standalone** Lean 4 package at `MathQL/` — a query language over SQLite
databases of mathematical objects, presenting a *mathematical* interface
(domains of objects with fields), never raw tables/SQL. No dependency on the
`lean/` folder or anything Danel did.

## Pipeline

```
parse     Parsing.lean   String → Input.Query                       Std.Internal.Parsec
typecheck Typing.lean    Context → Input.Query → Query               bidirectional check/infer
compile   Compile.lean   Database → Query → SQL.Query
render    SQL.lean       SQL.Query → String                         ToString, our own quoting
execute   Execute.lean   SQLite → Database → Query → IO (Except String Lean.Json)
```

## Type system (settled)

- `Ty` (`Ty.lean`): `int | bool | string | list t | prod ts`; hand-written
  `beq`/`LawfulBEq`.
- Intrinsic typing: `Expr` (`Expr.lean`, core AST), `ExprOfTy` (`Rules.lean`,
  declarative typing relation), bidirectional `check`/`infer` (`Typing.lean`)
  returning proof-carrying `{ e' // ExprOfTy Γ e' t }`.
- `defined`/`undefined` compile to `IS NOT NULL`/`IS NULL`; there is no `null`
  literal. SQL is three-valued (Kleene); `WHERE` is rendered **bare** (the sound
  reading — keep only rows where the condition is true).

## Query / Context / Database

- `Query` (`Query.lean`): `vars : List (Ident × DomainName)`, `condition : Expr`,
  `output : List (Ident × Label)`. The typing proof is dropped after checking;
  the compiler resolves columns through the `Database`.
- `Context` (`Context.lean`): typing side. `DomainTy { inputField : List (Label × Ty),
  outputField : List Label }`; `Entry := const Ty | domain DomainTy`.
  `Database.getContext` builds the `Context` used to type-check a query.
- `Database` (`Database.lean`): realization.
  - `Schema` (**Type 0**): `table`, `inputField : List (Label × InputField)`,
    `select : List String` (columns to project, in order).
  - `Domain extends Schema` (**Type 1**): adds `Obj : Type`,
    `decode : SQLite.RowReader Obj`, `outputField : List (Label × (Obj → Lean.Json))`.
  - `Database`: `const : List (Ident × Ty × SQL.Expr)`, `domain : List (DomainName × Domain)`.
  - *Why the split*: `Obj : Type` makes `Domain : Type 1`. The compiler needs
    only `Schema` (`Type 0`), so its `do`/`mapM` stays in `Type 0` (mixing a
    `Type 1` value into `Except`/`Option` bind is a universe error). Pull the
    schema with `match` on `Domain.toSchema`, never `Option.map`.

## Column decoding

- `Column` (`Column.lean`): `RowReader` helpers reading one column at its true
  type — `int`/`nat`/`bool`/`string`/`natOption`/`natList`. Integer columns go
  through `Int64` then convert: leansqlite's `ResultColumn Nat` reads a **BLOB**,
  so it must not be used for `INTEGER` columns.
- A domain's `decode` sequences these helpers; **struct field order ≡ `select`
  order ≡ decode order** is the positional contract SQLite does not check.

## graphs-small database

- `GraphsSmallDB.lean`: the `Database` for `data/graphs-small.db` (table `graph`,
  one domain `Graph`). `Graph` has semantic fields — `Nat`, `Bool`, `Option Nat`
  for the NULLable `diameter`/`radius`/`girth`, `List Nat` for the parsed
  `degree_sequence`. Schema taken from `data/graphs-small-description.md` and
  `python/generate_graphs.py`. Imports the umbrella, so it is **not** in the
  umbrella itself; check it with `lake env lean MathQL/GraphsSmallDB.lean`.

## What's done / next

Done and compiling: parse, typecheck, compile, render, execute, the `Column`
helpers, and a real `graphs-small` `Database`.

Next — the remaining half of the back end: a **runnable** that opens
`data/graphs-small.db`, sends a sample query string through the whole pipeline
(`Parsing.parse` → `checkQuery (database.getContext)` → `Execute.run db database`),
and prints the `Json`. This is what actually verifies the positional decode
order against real rows. After that: more domains, and wiring the MCP server
(the Python prototype is `python/mcp_server.py`).

## Build / test

```
cd MathQL
lake build                                # the library (umbrella MathQL.lean)
lake env lean MathQL/GraphsSmallDB.lean   # the graphs DB (not in the umbrella)
lake env lean Test.lean                   # front-end #guards + SQL-render #evals
```

`leansqlite` is a dependency at `.lake/packages/leansqlite` (FFI SQLite;
**typed, positional** row reading via `ResultColumn`/`Row`/`RowReader` — no
dynamic cell type). The databases live in `data/` (sibling of `MathQL/`):
`graphs-small.db`, `sym-ob-small.db`, with `*-description.md` for each.

## Conventions

- `autoImplicit := false`. No `mut` without permission. `check`/`infer` and
  `toSQL` work without `termination_by` — do not add it. No unrequested
  `deriving`.
- Spell identifiers out; no abbreviations (`Column`, not `Col`). No `·`
  placeholder currying — write `fun col => …`, not `(.col x ·)`. In `Except`/IO
  code prefer `return`/`throw` over `.ok`/`.error`. Use `open` sparingly;
  default to qualified names.
- Output is `Lean.Json` (standard library). There is no `Value` type.
- Never use the word "surface". `leansqlite` from git tracking `main`. Do not
  compile Mathlib. Ask before installing anything.
