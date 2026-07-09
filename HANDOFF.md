# Handoff

Branch `mathql-lean`. The library builds green (`lake build`). MathQL is a
**standalone** Lean 4 package at `MathQL/` — a query language over SQLite
databases of mathematical objects, presenting a *mathematical* interface
(domains of objects with fields), never raw tables/SQL. No dependency on the
`lean/` folder or anything Danel did. This package is the **reference
implementation**; a faithful pure-Python port lives in the sibling repo
`../bridge-mcp` (so MCP users need not install Lean) and must be kept in sync
with language changes made here.

## Pipeline

```
decode    QueryJson.lean  Json → Input.Query                         expressions parsed by Parsing
parse     Parsing.lean    String → Input.Expr                        Std.Internal.Parsec
typecheck Typing.lean     Context → Input.Query → Query              bidirectional check/infer/inferDomain
compile   Compile.lean    Database → Query → Result SQL.Query        hoisted LEFT JOINs, StateT
render    SQL.lean        SQL.Query → String                         ToString, our own quoting
execute   Execute.lean    SQLite → Database → Query → IO (Except String Lean.Json)
```

The `mathql` executable (`Main.lean`) serves this pipeline over stdin/stdout,
one JSON request per line; `{"describe": true}` returns the schema.

## Language (settled)

- `Ty` (`Ty.lean`): `int | bool | string | list t | prod ts`; hand-written
  `beq`/`LawfulBEq`; `Ty.prod'` elides a singleton product.
- **Expr/Domain split** (`Expr.lean`): `Domain` denotes objects — a domain
  variable, an object-by-primary-key `D[e…]` (`.obj`), or a domain-valued field
  — mutually with scalar `Expr`, which reaches objects only through `id` and
  field projection.
- Intrinsic typing: `ExprOfTy`/`DomainOfTy` (`Rules.lean`, declarative),
  bidirectional `check`/`infer`/`inferDomain` (`Typing.lean`) returning
  proof-carrying `{ e' // ExprOfTy Γ e' t }`.
- Output columns are checked independently in Γ (one may not refer to
  another); ORDER BY keys are checked in Γ extended with the output aliases and
  compile to bare-name `SQL.Expr.ref` references, which SQLite resolves against
  the output columns.
- String literals are SQL-standard: single-quoted, `''` for an embedded quote.
- `defined`/`undefined` compile to `IS NOT NULL`/`IS NULL`; applied to `id d`
  they test row presence via the first primary-key column. There is no `null`
  literal. SQL is three-valued (Kleene); `WHERE` is rendered **bare** (the
  sound reading — keep only rows where the condition is true).

## Query / Context / Database

- `Query` (`Query.lean`): `vars : List (Ident × DomainName)`, `condition : Expr`,
  `output : List (Ident × Ty × Expr)`, `limit`, `order`. The typing proof is
  dropped after checking; the compiler resolves columns through the `Database`.
- `Context` (`Context.lean`): typing side. `DomainTy { inputField : List (Label ×
  InputField), domainField : List (Label × DomainName) }` with `InputField { ty,
  isPrimary }`; `Entry := ty Ty | domain DomainName`. `Database.getContext`
  builds the `Context` used to type-check a query.
- `Database` (`Database.lean`): realization. `Schema { table, column : List
  (Label × Column), foreignKey : List (Label × ForeignKey), doc }` with
  `Column { column, ty, isPrimary, doc }`; `Database { overview, const :
  List (Ident × Ty × SQL.Expr), domain : List (DomainName × Schema), examples }`.
  `describe` renders the schema JSON served over MCP.
- Compilation (`Compile.lean`): a domain variable is a `FROM` alias; an `obj`
  or domain-valued field is hoisted to a `LEFT JOIN` with a fresh alias
  (`stem`, `stem2`, …, case-insensitive), one join shared by equal domain
  expressions. State lives in `StateT CompileState Result`.

## Result decoding

`Execute.decodeCell` reads each output column at its declared `Ty`: NULL is
JSON `null`; `list`/`prod` columns hold JSON text, parsed and returned
verbatim. Integer columns go through `Int64` then convert: leansqlite's
`ResultColumn Nat` reads a **BLOB**, so it must not be used for `INTEGER`
columns. (`Column.lean`'s `RowReader` helpers predate this type-directed
decode and are no longer used by the pipeline.)

## graphs-small database

- `GraphsSmallDB.lean`: the `Database` for `data/graphs-small.db` (table
  `graph`, one domain `Graph`, primary key `graph6`). Field types are `Ty` —
  `int`, `bool`, `string`, `list int` for `degree_sequence`; `diameter`/
  `radius`/`girth` are NULLable. Schema taken from
  `data/graphs-small-description.md` and `python/generate_graphs.py`. Imports
  the umbrella, so it is **not** in the umbrella itself.

## MCP server

`python/src/mathql_mcp/` packages the MCP server (`mathql-mcp` console
script): a persistent `mathql` subprocess spoken to over JSON lines, plus
networkx graph tools. `pip install -e python`, then point an MCP client at
`mathql-mcp`.

## Build / test

```
cd MathQL
lake build       # the library and the mathql executable
lake exe test    # front-end #guards + SQL-render #evals
lake exe mathql  # serve queries over stdin/stdout (default DB: ../data/graphs-small.db)
```

`leansqlite` is a dependency at `.lake/packages/leansqlite` (FFI SQLite;
**typed, positional** row reading via `ResultColumn`/`Row`/`RowReader` — no
dynamic cell type). The databases live in `data/` (sibling of `MathQL/`):
`graphs-small.db`, `sym-ob-small.db`, with `*-description.md` for each.

## Conventions

- `autoImplicit := false`. No `mut` without permission. `check`/`infer` work
  without `termination_by` — do not add it; `Compile.lean`'s mutual block
  carries `termination_by sizeOf`. No unrequested `deriving`.
- Spell identifiers out; no abbreviations (`Column`, not `Col`). No `·`
  placeholder currying — write `fun col => …`, not `(.col x ·)`. In `Except`/IO
  code prefer `return`/`throw` over `.ok`/`.error`. Use `open` sparingly;
  default to qualified names.
- Output is `Lean.Json` (standard library). There is no `Value` type.
- Never use the word "surface". `leansqlite` from git tracking `main`. Do not
  compile Mathlib. Ask before installing anything.
