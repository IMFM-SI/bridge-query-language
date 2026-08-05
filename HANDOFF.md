# Handoff

Branch `mathql-post-mono`. `lake build` is green, but `lake exe test` does not
compile — see **Plan: make this branch work** at the end of this file. MathQL is a
**standalone** Lean 4 package at `MathQL/` — a query language over SQLite
databases of mathematical objects, presenting a *mathematical* interface
(domains of objects with fields) to raw tables/SQL. No dependency on the
`lean/`. This package is the **reference implementation**; a faithful pure-Python
port lives in the sibling repo `../bridge-mcp` (so MCP users need not install Lean)
and must be kept in sync with language changes made here.

## Pipeline

```
decode    QueryJson.lean  Json → Input.Query                         expressions parsed by Parsing
parse     Parsing.lean    String → Input.Expr                        Std.Internal.Parsec
typecheck Typing.lean     Database → Input.Query → Query             bidirectional check/infer/inferDomain
compile   Compile.lean    Database → Query → Result SQL.Query        hoisted LEFT JOINs, StateT
render    SQL.lean        SQL.Query → String                         ToString, our own quoting
execute   Execute.lean    SQLite → Database → Query → IO (Except String Lean.Json)
evaluate  Execute.lean    the postprocess entries, per row, in Lean  evalPostExpr over Lean.Json
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
- **One `Expr` for every clause**: the condition, the output columns, the ORDER BY
  keys and the `postprocess` entries are all elaborated to the same `Expr`. It has
  two back-ends — `Compile.compileExpr` to SQL and `Execute.evalPostExpr` over
  `Lean.Json` — and the clause, not the term, decides which one runs.
  `Expr.call : Ident → List Expr → Expr` is typed by looking the name up in
  `Context.function`, seeded from `Database.sqlFunction` for the compiled clauses
  and from `Database.postFunction` for `postprocess`; a name is callable in a
  clause exactly when that clause's table holds it.
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
  `output : List (Ident × Ty × Expr)`, `postprocess : List (Ident × Ty × Expr)`,
  `limit`, `order`. The typing proof is dropped after checking; the compiler
  resolves columns through the `Database`.
- `Context` (`Context.lean`): typing side. `DomainTy { inputField : List (Label ×
  InputField), domainField : List (Label × DomainName) }` with `InputField { ty,
  isPrimary }`; `Entry := ty Ty | domain DomainName`;
  `function : List (Ident × (List Ty × Ty))`. `checkQuery` takes the `Database`
  and derives two contexts from it, `getSqlContext` and `getPostContext`.
- `Database` (`Database.lean`): realization. `Schema { table, column : List
  (Label × Column), foreignKey : List (Label × ForeignKey), doc }` with
  `Column { column, ty, isPrimary, doc }`; `Database { overview, const :
  List (Ident × Ty × SQL.Expr), domain : List (DomainName × Schema),
  sqlFunction : List (Ident × (List Ty × Ty) × String), postFunction :
  List (Ident × (List Ty × Ty) × (List Lean.Json → Result Lean.Json)),
  examples }`. `sqlFunction` names the SQL function a call compiles to;
  `postFunction` carries a Lean implementation. Both are `[]` in
  `GraphsSmallDB` and `SymObSmallDB`. `describe` renders the schema JSON served
  over MCP, and publishes neither function table.
- Compilation (`Compile.lean`): a domain variable is a `FROM` alias; an `obj`
  or domain-valued field is hoisted to a `LEFT JOIN` with a fresh alias
  (`stem`, `stem2`, …, case-insensitive), one join shared by equal domain
  expressions. State lives in `StateT CompileState Result`.

## Result decoding

`Execute.decodeCell` reads each output column at its declared `Ty`: NULL is
JSON `null`; `list`/`prod` columns hold JSON text, parsed and returned
verbatim — neither checked against the declared element or component types nor
normalised, so a `list int` column holding `["a"]` yields a value violating its
own `Ty`, and `2` written as `2.0` is not `BEq`-equal to `2`. Integer columns go
through `Int64` then convert: leansqlite's `ResultColumn Nat` reads a **BLOB**,
so it must not be used for `INTEGER` columns. (`Column.lean`'s `RowReader` helpers predate this type-directed
decode and are no longer used by the pipeline.)

## graphs-small database

- `GraphsSmallDB.lean`: the `Database` for `data/graphs-small.db` (table
  `graph`, one domain `Graph`, primary key `graph6`). Field types are `Ty` —
  `int`, `bool`, `string`, `list int` for `degree_sequence`; `diameter`/
  `radius`/`girth` are NULLable. Schema taken from
  `data/graphs-small-description.md` and `python/generate_graphs.py`. Imports
  `MathQL.Ty` and `MathQL.Database` rather than the umbrella, and is **not** in
  the umbrella itself.

## MCP server

`python/src/mathql_mcp/` packages the MCP server (`mathql-mcp` console
script): a persistent `mathql` subprocess spoken to over JSON lines, plus
networkx graph tools. `pip install -e python`, then point an MCP client at
`mathql-mcp`.

## Build / test

```
cd MathQL
lake build       # the library and the mathql executable
lake exe test    # front-end #guards + SQL-render #evals — BROKEN, see the plan
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

## Plan: make this branch work

Commit b1db0a2 ("Improve postprocessing") merged the separate `Expr`/`PostExpr`
datatypes into one `Expr` and gave calls a SQL image. It left five items to
finish. Do them in this order: each of the first four keeps `lake build` green on
its own, because `lean_exe test` is not a default target yet.

### 1. Give the parser a call production

`Input.Expr.call` has no producer. b1db0a2 deleted `Parsing.postExpr` — the only
parser that ever read `f(a, b)` — and added no call form to `expr`, so
`plus(n, 1)` parses `plus` as a bare identifier and then fails `eof` in
`runComplete`. The typing case in `Typing.lean`, the emission in `Compile.lean`
and `SQLExpr.lean`, and the evaluation case in `Execute.lean` are all unreachable
today, including the commit's own headline feature, calls in a condition.

Add one alternative to `identOrObjExpr` (`Parsing.lean:152`), between the `[`
branch and `pure (.ident x)`:

```lean
(do tok "("; let es ← sepBy expr (tok ","); tok ")"; return .call x es) <|>
```

`atomExpr` tries `idExpr` before it, so `id(g)` keeps its own meaning. Rename the
parser and its docstring to admit that it also reads a call.

### 2. Type-check the condition and the output in the extended context

`checkQuery` (`Typing.lean:238`) binds `sqlΓ := D.getSqlContext`, threads it
through `checkDomainVars` to obtain `Γ`, and then hands `sqlΓ` — not `Γ` — to
`check` for the condition and to `checkOutput`. The domain variables are out of
scope in both, so every query mentioning `g` fails with `unknown domain name g`.
ORDER BY alone still works, since it uses `Δ`, which is built from `Γ`.

Pass `D.getSqlContext` straight into `checkDomainVars` and use the returned `Γ`
everywhere below it. Dropping the `sqlΓ` binding leaves no unextended context in
scope to reach for again.

### 3. Put the output aliases in scope for `postprocess`

`checkPostprocess` receives `D.getPostContext`, whose `ident` holds the database
constants alone, so no entry can name an output column — which is the whole point
of the clause. Fold the output aliases onto it, exactly as `Typing.lean:245` folds
them onto `Γ` for ORDER BY; two uses justify one `Context.extendOutput`.

Losing that fold also lost a check. `checkPostprocess` rejects shadowing by
looking the name up in the context, so an entry may currently reuse an output
alias, and `run` then emits a row (`row ++ post`) carrying that name twice.
Restoring the fold restores the check.

Settle one asymmetry while here: `getPostContext` puts `D.const` in scope, but
`collectRows` seeds `PostEnvironment.ident` with the row alone, so a constant in a
`postprocess` entry type-checks and then evaluates to `null`. `Database.const`
holds `SQL.Expr` values, with no `Lean.Json` to seed the environment with, so the
simple fix is to drop `const` from `getPostContext`.

### 4. Make comparison in `postprocess` behave like SQL

`evalPostExpr` discards the `Ty` that `Expr.compare` carries
(`| .compare op _ e1 e2`), and `evalComparison` reads both operands through
`getInt?`, so a well-typed comparison at `string`, `bool`, `list` or `prod` fails
and the field silently becomes `null`. `compileExpr` does use that `Ty`, wrapping
list and product operands in `json(…)`.

The governing principle is that `postprocess` should not differ from SQL. Let the
`Ty` choose a comparable key and interpret the operator once over an `Ordering`.
Both instances this needs, `Ord Bool` and `Lean.Json.compress`, are in core.

```lean
/-- Compare two JSON values at their MathQL type as SQLite does: numerically at
    `int` and `bool`, lexicographically at `string`, and on canonical JSON text
    at `list` and `prod`. -/
def compareJson : Ty → Lean.Json → Lean.Json → Result Ordering
  | .int,    j₁, j₂ => do return compare (← j₁.getInt?) (← j₂.getInt?)
  | .bool,   j₁, j₂ => do return compare (← j₁.getBool?) (← j₂.getBool?)
  | .string, j₁, j₂ => do return compare (← j₁.getStr?) (← j₂.getStr?)
  | .list _, j₁, j₂
  | .prod _, j₁, j₂ => return compare j₁.compress j₂.compress

def evalComparison (op : ComparisonOp) (t : Ty) (j₁ j₂ : Lean.Json) :
    Result Lean.Json :=
  match j₁, j₂ with
  | .null, _ | _, .null => return .null
  | _, _ => do
    let c ← compareJson t j₁ j₂
    return .bool <| match op with
      | .eq => c.isEq | .ne => c.isNe
      | .lt => c.isLT | .le => c.isLE
      | .gt => c.isGT | .ge => c.isGE
```

Then pass the type through: `| .compare op t e₁ e₂ => … evalComparison op t v₁ v₂`.

Equality agrees with SQL at every type; the orderings agree at `int`, `bool` and
`string`, and on lists and products they reproduce SQLite's own text order,
arbitrary as that is (`[10] < [9]`). A `null` operand yields `null`, the one piece
of SQL's null behaviour worth paying for, since nullable columns make it reachable.
Three divergences stay, deliberately: SQL's three-valued `AND`/`OR` (a `null`
comparison reaching `&&` fails in `getBool?`, so the whole field becomes `null`,
where SQL answers `NULL AND false = false`), SQLite's 64-bit arithmetic against
Lean's arbitrary-precision `Int`, and collations other than BINARY.

### 5. Repair `Test.lean` and build it

`MathQL/Test.lean` is byte-identical to the pre-unification version and does not
compile: `toyDB` omits the now-required `sqlFunction` and `postFunction` fields;
`elaborates` and `renderOf` call `checkQuery (Context.empty toyCtx)`, where
`checkQuery` takes a `Database` and `Context.empty` takes two arguments; and the
`call` helper reaches for `Postprocess.functionsImpl`, in a module since removed.
Nothing caught any of it because `lean_exe test` carries no `@[default_target]`,
so `lake build` never elaborates the file.

- Give `toyDB` its own function fixtures rather than a library table: one
  `postFunction` entry for the postprocess tests to call, and one `sqlFunction`
  entry whose SQL name differs from its MathQL name, so a test can pin which of
  the two gets emitted.
- Point `elaborates` and `renderOf` at `checkQuery toyDB`. `toyCtx` and
  `Context.empty` then have no user left, and `Context.empty` can go.
- Delete the `call` helper (70–75) and the `power`/`factorize` guards (160–186),
  which tested the removed `Postprocess` module.
- Fix two comments that now state the opposite of the design. `foo(3)` *is*
  syntax (line 99): it is rejected by the function-table lookup, like `bogus(1,2)`
  at 139. And `PostExpr` no longer exists (line 142) — that guard still holds, but
  because `getPostContext` has `domain := []`.
- Add what neither this branch nor its predecessor covers: a call in a condition
  rendering to SQL, the same call in a `postprocess` entry evaluating in Lean,
  comparison at each `Ty`, and a `null` operand.
- Last, mark `lean_exe test` `@[default_target]`, so this class of breakage cannot
  recur. Doing it earlier would stop the intermediate commits from building.

### Known gaps, deliberately out of scope

Recorded so they are not rediscovered as surprises. None blocks the above.

- Both shipped databases register `sqlFunction := []` and `postFunction := []`,
  so no function is callable in a real query. `postprocess` remains useful without
  one, since an entry is a full expression: `n + 1`, `n == m`, `d.0`, `if`, lists,
  tuples. Choosing a set of builtins is separate work.
- `defined`/`undefined` in `postprocess` test whether evaluation succeeded
  (`Execute.lean:147`), where SQL tests `IS NOT NULL`. The principle behind §4
  says they should test JSON-nullness.
- `evalPostprocess` (`Execute.lean:160`) collapses every evaluation error to
  `null`, discarding the messages the unification introduced.
- `Database.describe` publishes neither function table, so nothing tells an agent
  which functions a database offers.
- The MCP `query` tool takes no `postprocess` argument
  (`python/src/mathql_mcp/query_tools.py:31`), so the clause cannot be reached
  over MCP however well it works in Lean.
- `docs/query-grammar.md` documents neither the `postprocess` clause nor the call
  form. `LANGUAGE.md:172` and `PLAN.md:113` both assert "there is no separate
  evaluator", which `Execute.evalPostExpr` contradicts, and `LANGUAGE.md:133` says
  a row is a JSON object where `Execute.run` emits `[name, value]` pairs.
