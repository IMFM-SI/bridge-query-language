# PostgreSQL backend design

Status and document authority: [README.md](README.md). Module ownership: [ARCHITECTURE.md](ARCHITECTURE.md). Acceptance checks: [IMPLEMENTATION.md](IMPLEMENTATION.md).

## Scope and compatibility

**CORE-01 — Independent backends.** Add PostgreSQL while preserving the existing SQLite implementation and request protocol. Each backend owns compilation, SQL AST/rendering, connections and decoding. PostgreSQL compiles checked MathQL directly; neither backend translates through or imports the other. Share the parser, checker, language types, logical dataset descriptions and Lean postprocessor. Avoid a universal SQL framework, plugin system or compatibility flags. Small helpers may be shared if they do not select database behavior.

**CORE-02 — Preserve the language and baseline.** Preserve syntax, types, typing rules, object lookup semantics, output order and postprocessing. Backend-specific constant and SQL function catalogues are explicitly permitted by CONST-01 and FUNC-01. Do not normalize native SQL arithmetic, overflow, null ordering, text collation or collection comparisons across backends. Document differences and executed evidence in DIFFERENCES.

**CORE-03 — Native evaluation.** PostgreSQL uses native bigint arithmetic and JSONB equality/ordering, including nested collections; no text casts for collection comparisons or custom helpers to force matching results. Division by zero is a query error; do not replace a zero divisor with NULL to suppress it. This restriction does not prohibit TYPE-03's conversion of JSON null to SQL NULL. SQLite retains its existing behavior. Lean postprocessing remains independent, including entry-level error-to-null conversion and declaration-order evaluation. The division and collection examples in [DIFFERENCES.md](DIFFERENCES.md) are required regression cases. Unordered rows and ties without a tie-breaker have no guaranteed order.

## Registrations and shared interfaces

**CONST-01 — Independent backend constants.** Remove constants from shared `Database` and dataset descriptions. Each backend owns complete per-dataset registrations: MathQL name, MathQL `Ty` and its own SQL expression. `SQLite/Constants.lean` defines `List (Ident × Ty × SQLite.SQL.Expr)`; `PostgreSQL/Constants.lean` defines `List (Ident × Ty × PostgreSQL.SQL.Expr)` in the planned namespaces. A constant may exist on only one backend; the same name may have different types and values on different backends. Each registration keeps its type and SQL expression together; derive checker signatures and compiler bindings from the same selected registrations. A constant not registered on the selected backend is an unknown identifier during checking, with no fallback to another backend. There is no shared constant catalogue, intersection, required counterpart or cross-backend compatibility requirement. Both datasets currently register no constants.

**FUNC-01 — Selected SQL function catalogue.** Select dataset and backend before checking. Remove `sqlFunction` from shared `Database` and dataset descriptions (baseline: `Database.sqlFunction : List (Ident × (List Ty × Ty) × String)`, read by `Database.getSqlContext` and `compileQuery`). Each backend's `Functions.lean` owns complete per-dataset registrations: MathQL name, argument types, return type and backend SQL binding. SQLite may keep the baseline binding shape; PostgreSQL defines its own binding type in its namespace, rendered with schema qualification per RUN-03. Derive the checker signatures and compiler mappings from the same registrations. One registration per name; no overloading. Names and signatures may differ between backends. Checking rejects unavailable or wrongly applied functions, without fallback. Registrations describe existing SQL functions; installation belongs in setup, not runtime. Both datasets currently register no SQL functions.

**FUNC-02 — Independent postprocessing.** Keep shared `postFunction` signatures and Lean implementations separate. SQL registrations do not make names available in postprocessing. Postprocessing receives decoded rows and evaluates entries in order, allowing later entries to use earlier ones.

**API-01 — Checker inputs.** Shared checking receives domains and the selected backend's constant and SQL function signatures as data, with no backend imports or backend-name branches. The selected compiler receives the matching bindings and shared metadata. Preserve identifier shadowing and output-name resolution from the current checker/compiler.

**API-02 — Handle types locally in PostgreSQL compilation.** Keep the shared `Expr` and `Query` representations unchanged; do not add per-expression annotations or refactor SQLite/postprocessing to supply PostgreSQL with types. PostgreSQL compilation uses the information already available: checked output types, comparison operand types, field/key metadata, selected constant/function signatures, literals and the existing `unaryTy`/`binaryTy` operator rules. Small helpers inside `PostgreSQL/Compile.lean` or `Types.lean` may determine expression/component types when needed. Pass expected types down from outputs, boolean conditions, comparisons, function arguments and enclosing collections/conditionals, including to empty lists. Resolve output references using their checked types and expressions, preserving shadowing when substituting sort expressions. Reuse existing type rules rather than introducing a second proof-producing checker or rechecking the input query. User syntax, typing rules and evaluation behavior remain unchanged.

Use PostgreSQL's existing SQL types and type resolution wherever sufficient. Do not cast every expression: a bigint column can participate directly in arithmetic. Add casts where PostgreSQL needs them, such as converting an integer JSONB component extracted as text to bigint, resolving an otherwise ambiguous parameter, or ensuring literal-only arithmetic uses bigint. Choose scalar versus collection extraction using local MathQL type information; do not infer MathQL types by inspecting generated SQL or JSON values. Do not restrict accepted expressions or expand the shared representation to bypass missing type context; use the conflict-handling instruction in [README.md](README.md).

**API-03 — Ordered results and describe.** Both executors return ordered `List (Ident × Lean.Json)` rows to the shared runner. Preserve existing response fields and row ordering. `describe` keeps its existing fields and lists only the selected backend's constants, preserving the entry shape `{"name": ..., "type": ...}`. It does not list SQL functions.

## Configuration and runtime

**CLI-01 — Selection and compatibility.** Preserve `mathql [database-name] [sqlite-path]`, defaulting to `graphs-small` and its configured SQLite file. The first positional argument is a logical dataset name, despite stale README wording; the second remains the only way to give a SQLite path. Add `--backend` and an optional `--connection`:

```text
mathql graphs-small ../data/graphs-small.db
mathql graphs-small --backend postgres
mathql sym-ob-small --backend postgres --connection "host=localhost user=mathql"
```

Keep an explicit registry mapping `graphs-small` to SQLite `data/graphs-small.db` / PostgreSQL schema `graphs_small`, and `sym-ob-small` to `data/sym-ob-small.db` / schema `sym_ob_small`. Reject unknown datasets/options, a SQLite path with PostgreSQL, and `--connection` with SQLite. Default to SQLite; never fall back after a PostgreSQL failure.

**CLI-02 — Connection settings.** Use libpq's standard connection settings: its environment variables (`PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`, …) and its default files (`~/.pgpass`, `pg_service.conf`). `--connection` takes a libpq connection string, passed to libpq unchanged; its values override the environment. Trust the resulting settings, including the database; do not add a custom configuration-file format or override the database libpq selects.

**RUN-01 — Resource ownership.** Keep one connection per process and a sequential request loop, with no pool. Backends open/close connections, discover columns, execute and release results. PostgreSQL uses a read-only role and read-only session/transaction settings. Prefer ordinary standalone query execution; do not add per-request transactions solely for this backend. If the driver or implementation uses an explicit transaction, roll it back after failure so the next request works. SQLite remains read-only.

**RUN-02 — Error channels.** Configuration, connection and startup metadata failures write diagnostics to stderr and exit nonzero before reading requests. This deliberately changes the baseline, where an unknown dataset name prints to stderr but exits 0; CLI-01's preserved legacy behavior covers argument forms and defaults, not exit codes. Once serving, malformed JSON, parsing, checking, compilation and execution failures return one `{"error":"..."}` response for that request; continue with the next request when the connection remains usable. Keep stdout exclusively JSON Lines. Do not send failed requests through successful row processing.

**RUN-03 — Physical names.** Qualify dataset tables and functions with the selected schema and quote each identifier separately, e.g. `"graphs_small"."graph"`. Do not rely on inherited `search_path` or fall back to `public`; normal PostgreSQL built-ins remain available. Bind metadata-query values and report missing objects. Use physical column names for collision-free generated aliases. SQLite retains its existing hidden-row-name exclusions; PostgreSQL does not copy them.

## PostgreSQL values and SQL compilation

**TYPE-01 — Representation.** Stored columns and compiled scalar results use `bigint`, `boolean`, `text` for MathQL int, bool, string. All lists and products use positional `jsonb` arrays at every depth. Ragged/nested lists and heterogeneous products must work. Single-column object IDs remain scalars; multi-column IDs use arrays in key order. Unit products are `[]`; an explicit one-component product remains a one-element array. JSONB alone does not enforce MathQL collection types; checking and recursive import validation do. Preserve exact integers during import and decoding.

**TYPE-02 — Construction.** Compile query collections as `to_jsonb(ARRAY[to_jsonb(e1), ...]::jsonb[])`, with each element having a known SQL type. The empty form is `to_jsonb(ARRAY[]::jsonb[])`. Use the same construction for every size, avoiding variadic function argument limits without chunking. The temporary one-dimensional SQL array contains JSONB elements; nested JSON arrays are not extra SQL dimensions. Normal database resource limits still apply. For already serialized collections, bind JSON text as `$1::jsonb`; `to_jsonb(text)` would encode a string instead of parsing the collection.

```sql
-- Ragged list [[1], [2, 3]]
SELECT to_jsonb(ARRAY[
  to_jsonb(ARRAY[to_jsonb(1::bigint)]::jsonb[]),
  to_jsonb(ARRAY[to_jsonb(2::bigint), to_jsonb(3::bigint)]::jsonb[])
]::jsonb[]);

-- Product (1, 'hello', true)
SELECT to_jsonb(ARRAY[
  to_jsonb(1::bigint), to_jsonb('hello'::text), to_jsonb(TRUE)
]::jsonb[]);
```

**TYPE-03 — Nulls and projection.** SQL NULL represents absence of a whole value; `[]` is a present empty collection; JSON null is an absent component inside a collection. Constructors preserve absent components, e.g. `[null, 1]`, without suppressing evaluation errors. Tuple projection is zero-based and applies to products, not lists. Extract integers with `(value ->> i)::bigint`, booleans with a boolean cast, strings with `->>`, and collection components with `NULLIF(value -> i, 'null'::jsonb)`. Thus projected absence becomes SQL NULL for presence tests. Importers must normalize a top-level JSON null collection to SQL NULL, while retaining nested nulls.

**TYPE-04 — Scalar operations and decoding.** Explicitly type literals/parameters where needed to keep scalar arithmetic in bigint rather than accidental int32 or generic JSON arithmetic. Decode using the expected MathQL type, preserving nulls, booleans, exact numbers, strings, positional arrays and nesting. Convert the driver's JSON/text representation to `Lean.Json`; never parse PostgreSQL array/record syntax as JSON. Any output-only JSON text conversion stays outside filtering and ordering.

**SQL-01 — Objects and query shape.** Implement every current expression/operator. Preserve repeated-join reuse, missing-object LEFT JOIN semantics, key order and the first-primary-key-column test for `defined id(o)`. Put explicit CROSS JOINs before generated LEFT JOINs so join conditions can refer to all base domains. Support no domains, no output and object lookups without a base table. Use an aliased synthetic `(SELECT 1)` source when necessary; retain `SELECT 1` as the internal empty-output placeholder but return an empty output row. Preserve generated `c1`, `c2`, ... alias collision avoidance and removal of constant sort keys.

**SQL-02 — Output references in sorting.** A bare output alias may be used directly in PostgreSQL ORDER BY. Inside a larger sort expression, use simple expression substitution when repeated evaluation preserves the value; use an enclosing query when the output value must be referenced instead. Preserve output alias shadowing, hidden sort inputs and ORDER BY/LIMIT behavior. Do not duplicate an output function call if repeated evaluation could change the value used for sorting. Choose the smallest query structure that preserves these semantics; no mandatory CTE strategy, function-volatility registry or call-count instrumentation framework is required. Additional materialization is needed only if the implemented function bindings and chosen query structure require it for correctness.

**SQL-03 — Safe generation.** Bind runtime values where the driver supports parameters, quote identifiers separately and never accept raw user SQL via constant, function or schema names. Keep generated SQL and ordered bound values together. Constants and function bindings are explicit trusted Lean definitions, not user-supplied SQL fragments.

## Driver and import

**DEP-01 — Prove the driver first.** The proposed binding is [paulbutcher/leanpostgres](https://github.com/paulbutcher/leanpostgres), imported as `Postgres`; compatibility is not yet established. Pin a revision compatible with the project's `leanprover/lean4:v4.35.0-rc2`, inspect its actual package/API and regenerate the Lake manifest. Retain `leansqlite` and the Lean version. Demonstrate bound queries and scalar/null/JSONB conversion to `Lean.Json`, exact integer handling, cleanup and error recovery before full integration. Verify Windows libpq build and DLL discovery. Record tested Lean, driver and PostgreSQL versions and platform setup; if compatibility fails, report the blocker instead of silently upgrading Lean or swapping drivers.

**IMPORT-01 — Repeatable, scoped importer.** Put the importer, conversion rules, schema SQL and pinned Python PostgreSQL dependency under `python/postgresql/`; use Python `sqlite3` to read sources read-only. Create `mathql` once during setup. The importer creates the selected dataset schema or rebuilds it only with an explicit reset option. Never drop the database or another schema; use transactions to avoid partial imports. Keep each dataset's tables, functions, constraints and any sequences/types within its schema. Preserve existing SQLite files and unrelated Python files.

**IMPORT-02 — Mapping.** Import the tables the Lean descriptions map: graphs-small's `graph` and sym-ob-small's `graph`, `maniplex`, `canonicallabeling`, `clparameters`, `graphexternalreference`. Convert `degree_sequence`, `vertices_in_canonical_order`, `schlafli_symbol`, `generators` (integer lists) and `color_group` (nested lists) from JSON text to `jsonb`, and 0/1 booleans to `boolean`; keep declared strings as text even if they look like JSON. Fail on a value that does not match its declared type. Preserve IDs, primary keys and foreign-key values, and add the indexes that joins need.

**IMPORT-03 — Verification.** Insert in batches. Errors identify the table and column. After an import, check each table's row count against the source and spot-check representative values, including booleans and collections. Reimport whenever storage mappings change.

## Non-goals

Features such as function overloading, general migration/database plugin frameworks and cross-backend result normalization are outside this implementation. Focus on implementing specifically what is described in the given documents.
