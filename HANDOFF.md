# Handoff

Branch: `mathql-lean`. The working tree is mid-redesign of MathQL's type
system and database model. It likely does not build (see *Current state*).
This session was design only; the uncommitted edits predate the final
decisions recorded below.

## Converged design

### Type system

- `Ty` is ground-only and closed: `int | bool | string | list | prod`. No
  `name`, `record`, `enum`, or `option`. `Ty.interpret` is total and
  model-free — there is no `NameModel`/`M`.
- Named types are *domains*. A domain name appears only as the collection a
  variable ranges over (`x ∈ C`). A record is not a value type: a table is not
  storable in a column, and a primary key is a ground value, not a table.

### Variables and terms

- Every query variable refers to a domain. The context maps a variable to a
  domain name, not to a `Ty`.
- There is no bare-variable term. The atoms are projections off a domain
  variable, `x.label`. The variable doubles as the SQL table alias.
- Binding several domain variables (`x ∈ C, y ∈ D`) is a join across tables.

### Two kinds of domain accessor

- *Invariants*: backed by one SQL column, ground `Ty`. Usable in conditions
  and output.
- *Representations*: Lean functions of the fetched row, output only, not
  described by `Ty` (e.g. `graph6 : String`, `edgeList`). Many just return an
  invariant's value.

### Two-world execution

- The condition `φ` is a `Ty`-typed boolean over invariants. It compiles to a
  SQL `WHERE` clause. No re-filter, no `DB.correct`.
- The output is a tuple of representations. Fetch the columns those
  representations need, then build the tuple in Lean. `Ty` lives only on the
  query side; the output lives in Lean.

### Constants (replacing enums)

- The schema declares named constants, each `Ident ↦ (ground Ty, SQL
  translation)`, e.g. `polytopal : string ↦ 'polytopal'`. A constant is a
  0-ary op with a fixed ground type and a fixed SQL literal. `Expr.enum` /
  `Input.enumCtor` becomes a constant reference resolved against this table.
- `NULL` is a built-in polymorphic constant: it checks against any ground
  type. `== NULL` / `!= NULL` must compile to `IS NULL` / `IS NOT NULL`, not
  `= NULL`. `NULL == NULL` has nothing to infer — reject it or fix a meaning.

### Operations

Fixed standard meaning (no `OpModel`).

### Database (single database)

`Database` holds `domains` and a constants table. A `Domain` has its name,
table/alias, invariants (label, ground `Ty`, column), representations (Lean
functions), and a decode for the columns a query needs. No `Enum` structure,
no `M`/`NameModel`, no per-object `Obj` interpretation for conditions.

## Current state of the code

The uncommitted edits lag the design above:

- `Ty.lean`: `name` renamed to `enum` (still a `Ty` constructor); `option`,
  `list`, `prod` still present. Per the design, `enum` and `option` should
  both go, leaving `int | bool | string | list | prod`.
- `Context.lean`: `var : List (Ident × Ident)` (variable ↦ domain) is right,
  but `lookupVar` still returns `Option Ty` over `Γ.var.lookup`, which now
  yields `Option Ident` — a type mismatch, the likely build break.
- `Database.lean` (new): `Field`, `Domain`, `Enum`, `Database`. Close to the
  design but still has `Enum` (should become a constants table) and has no
  representations or decode yet.
- The rest (`Expr`, `Rules`, `Input`, `Parsing`, `Typing`, `Test`) is
  unchanged and still assumes the old model: variables have a `Ty`, results
  are `Ty`-typed `Expr`, enums are named types.

I did not run a build.

## Next steps

1. Settle `Ty` to `int | bool | string | list | prod` (drop `enum`,
   `option`); simplify `Ty.beq` / `LawfulBEq`. `Ty.interpret` becomes
   total and model-free.
2. Fix `Context`: variable ↦ domain; add lookups for a domain's invariants
   and representations, and for schema constants. `lookupVar` returns the
   domain name.
3. `Database.lean`: drop `Enum`, add a constants table (`Ident ↦ Ty × SQL`);
   add representations (Lean functions) and a row decode to `Domain`.
4. Rework `Expr` / `Rules`: the condition `Expr` keeps literals/ops/
   projection/tuple; replace `var` with a projection node carrying
   `(variable, label)`; `ExprOfTy` is for conditions only. The result becomes
   a tuple of representation references, not a `Ty`-typed `Expr`.
5. `Input` / `Parsing` / `Typing`: surface = domain bindings + condition +
   output tuple of representations; `checkQuery` checks the condition against
   invariants/constants and resolves output representations by name; enum →
   constant.
6. Compile condition → SQL `WHERE`; fetch + decode; build the output tuple in
   Lean. Reuse Danel's `lean/QueryLanguage/{Core,Graph/SymObSmallDB}.lean`
   for `Tm.toSQL`, `collect`/fetch, and leansqlite usage.

## Constraints and preferences

- `autoImplicit := false` project-wide.
- No `mut` without explicit permission. `check`/`infer` work without
  `termination_by` — do not add it.
- No `deriving` clauses that were not requested.
- Naming: `es` for expression lists, `e₁`/`e₂` for two expressions. No
  wildcard `_` in the typing match — list all cases.
- Never use the word "surface".
- `leansqlite` from git, tracking `main`. Do not compile Mathlib. Ask before
  installing anything.

The stale design notes live at
`~/.claude/plans/no-don-t-run-it-stateful-dahl.md`; this file supersedes
their design section.
