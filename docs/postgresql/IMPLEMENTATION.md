# PostgreSQL backend implementation and acceptance

Implement [DESIGN.md](DESIGN.md) using the ownership in [ARCHITECTURE.md](ARCHITECTURE.md). Each milestone must leave the package buildable. Requirement references below identify what to verify, not alternative definitions of the requirements.

At each handoff, report changed files, requirement IDs covered, exact commands/results and remaining questions. Distinguish pure tests, SQLite execution tests, PostgreSQL execution tests and importer tests. A test requiring unavailable services or data is unverified, not passed. Record tested versions and concrete backend outcomes in DIFFERENCES.

Keep verification proportional to the changes. Existing tests may satisfy acceptance checks; one focused case may cover several requirements. Reuse passing evidence when the tested code and dependencies have not changed. No separate test framework, benchmark suite or exhaustive combination of all cases is required.

## M1 — Verify the PostgreSQL driver works for MathQL's needs

References: CORE-01, CORE-02, DEP-01.

Read current Main, Database, Compile, SQLExpr, SQL, Execute, Column and the checker before refactoring. Baseline observations at `076d954` include SQLite-specific booleans/JSON operations, `Database.const` containing SQL expressions, and postprocessing inside Execute. Verify rather than assuming these observations still hold. `Test.lean` has mainly compile-time `#guard` checks and a no-op main in that baseline; `lake exe test` alone is not live database coverage.

Acceptance:

- [ ] Run `lake build` and `lake exe test` from `MathQL/`; record baseline failures before changes.
- [ ] Pin and build a compatible driver without changing Lean or removing SQLite.
- [ ] Demonstrate a bound query and correct scalar, null and JSONB decoding into `Lean.Json`, preserving integers exactly across the PostgreSQL `bigint` range.
- [ ] Demonstrate that a valid query succeeds after a failed query and that results/connections are released. Use the driver's normal execution mode; explicit transactions are not required for this check.
- [ ] Record tested Lean/driver/PostgreSQL versions and Windows libpq include/library/DLL setup. If the driver checks fail, report it before proceeding with full integration.

## M2 — Separate SQLite from shared code

References: CORE-01, CORE-02, CONST-01, CONST-02, FUNC-01, FUNC-02, API-01, API-02, API-03.

Acceptance:

- [ ] Move SQLite modules and extract Postprocess following ARCHITECTURE; no shared frontend/metadata/postprocessor imports a backend or driver.
- [ ] Keep shared Expr/Query representations unchanged. Adapt checker inputs for selected registrations without adding per-expression annotations or changing SQLite/postprocessing type handling.
- [ ] Select registrations before checking and derive matching function signatures/bindings from one registration set.
- [ ] Exercise nonempty SQLite constant registrations containing names, types and SQL expressions; reject duplicate names within the selected dataset/backend at configuration time. Confirm shared dataset descriptions no longer contain constants.
- [ ] Exercise SQLite-only/unavailable functions, wrong argument counts/types and duplicate registrations. Preserve separate postprocessing functions.
- [ ] Verify `describe` preserves existing fields, lists only selected-backend constant signatures, and emits API-03's exact additive functions shape, including an empty array.
- [ ] Preserve existing guards, legacy CLI behavior and actual SQLite execution results, including the division/postprocessing examples in DIFFERENCES.
- [ ] Run `lake build` and `lake exe test`; add explicit execution checks rather than relabeling compile-time guards as integration tests.

Independent PostgreSQL registration coverage becomes mandatory in M3; no live PostgreSQL connection is needed for those registration checks.

## M3 — PostgreSQL configuration and scalar queries

References: CONST-01, CONST-02, FUNC-01, API-01, API-02, API-03, CLI-01, CLI-02, RUN-01, RUN-02, RUN-03, TYPE-01, TYPE-04, SQL-01, SQL-03.

Acceptance:

- [ ] Implement dataset/backend selection and connection settings; test legacy forms, both datasets, unknown/conflicting options, wrong database, inherited settings, quoted/empty env values and invalid env lines.
- [ ] Validate each backend's constant registrations independently in pure tests, including CONST-02 duplicate-name errors. Cover SQLite-only and PostgreSQL-only constants and the same constant name with different types and values. Verify unavailable constants fail checking, selected signatures reach `describe`, matching SQL expressions reach the compiler, and no cross-backend coverage check or fallback exists. Verify selected-backend startup errors occur before request processing.
- [ ] Cover PostgreSQL-only and SQLite-only functions and the same name with differing signatures; checking, compilation and `describe` use the same selected registrations.
- [ ] Implement PostgreSQL-local type helpers using the existing checked output/comparison types, metadata, selected registrations and operator rules. Pass expected types from enclosing expressions where needed; do not change shared Expr/Query or introduce a second checker.
- [ ] Verify bool/int/string/null results, bigint boundary/overflow behavior, signed division, zero division and exact decoding. Inspect generated SQL to confirm already typed columns are used directly and casts are added only where needed, including bigint literal arithmetic and ambiguous parameters.
- [ ] Verify quotes, backslashes and Unicode through bound values, plus separately quoted schema/object names.
- [ ] Cover no domains/output, missing objects, single-column IDs, repeated joins, multiple base domains and alias collisions. Composite-ID coverage follows in M4 with collection support.
- [ ] Confirm connection/metadata/configuration failures use stderr/nonzero exit; malformed JSON and query-stage failures produce JSON error responses with no credential leakage. A valid request after a query error succeeds.
- [ ] Confirm read-only operation and schema isolation; PostgreSQL does not fall back to SQLite or public.

## M4 — Collections and sorting

References: CORE-03, API-02, TYPE-01, TYPE-02, TYPE-03, TYPE-04, SQL-01, SQL-02.

Acceptance:

- [ ] Cover every expression/operator using PostgreSQL-local type handling: empty/nested lists receiving expected types, product projection in arithmetic/function arguments/comparisons, object-key arguments and selected-backend constant types. Verify output references and sorting substitutions preserve the correct type context and identifier meaning.
- [ ] Check that integer/boolean JSONB projections receive necessary conversions, text projections use text extraction, and collection projections preserve JSONB with TYPE-03 null handling. Verify these cases without adding shared per-expression annotations or changing SQLite behavior.
- [ ] On PostgreSQL, cover empty and one-element lists/products, plus a collection with more than 100 elements to catch variadic-constructor limits. Verify lengths, order, types and nesting using representative cases without chunking. A full size-by-type matrix or stress benchmark is not required. These constructor checks do not impose a new policy on SQLite.
- [ ] Test ragged/nested lists, empty/unit/one-component products, mixed products, SQL NULL versus empty collections, nested JSON null and presence tests after projection.
- [ ] Bind serialized JSON collections separately; verify they decode as arrays rather than strings. Inspect PostgreSQL result/column types in addition to response JSON.
- [ ] Verify multi-column ID key order and the first-key-column presence test for missing objects.
- [ ] Test bare output aliases, compound sort expressions, alias shadowing, hidden sort inputs, constant sort removal, ascending/descending order and LIMIT placement.
- [ ] Cover output references in compound sort expressions with a representative registered function. If the implementation includes functions whose values can change between calls, add a focused regression for reuse of the output value; do not introduce such functions or a general call-count framework solely to satisfy this milestone.
- [ ] Execute DIFFERENCES' scalar/collection division and native comparison cases with separate expected results for SQLite, PostgreSQL and postprocessing. Also record null ordering, text collation and overflow outcomes for tested versions.

## M5 — Import both datasets and integrate

References: IMPORT-01, IMPORT-02, IMPORT-03, RUN-03, TYPE-01, TYPE-03, TYPE-04, SQL-01.

Acceptance:

- [ ] Add pinned importer dependencies, explicit source mappings and recursively validated conversions for all named collection fields/tables.
- [ ] Cover invalid booleans, malformed JSON, wrong element types/product component counts, bigint overflow, empty values, nested nulls and top-level JSON-null normalization.
- [ ] Verify source files remain read-only and failures identify table/key/column and do not commit partial imports.
- [ ] Check row counts, exact key sets, constraints/indexes, orphan reporting, null counts and representative scalar/collection values for both datasets.
- [ ] Execute representative dataset examples, missing-object and two-hop traversal queries through the Lean executable.
- [ ] In explicitly designated test schemas, prove reset requires its explicit option and rebuilding one dataset leaves the other intact. Never reset production data as an incidental test action.
- [ ] Demonstrate bounded-memory batch/stream import of the maniplex source.
- [ ] Run SQLite regressions and PostgreSQL live tests after import; reimport test data after storage-mapping changes.

## M6 — Final documentation and completion

References: all DESIGN requirements.

Acceptance:

- [ ] Assemble passing evidence for `lake build`, `lake exe test`, added live backend tests and importer/conversion tests; record exact commands and prerequisites. Rerun checks affected by subsequent changes; do not repeat unchanged checks solely for handoff.
- [ ] Document actual setup, pinned versions, libpq installation, connection/env behavior, importer commands and test commands in the appropriate repository usage docs.
- [ ] Correct stale README CLI guidance and LANGUAGE passages that present SQLite division/comparison behavior as universal.
- [ ] Add actual outcomes, versions and test references to DIFFERENCES; preserve labels for unexecuted expectations.
- [ ] Confirm every requirement ID has acceptance evidence or an explicitly reported unresolved limitation. Completion requires both datasets imported and queried successfully on PostgreSQL and passing SQLite regressions; unavailable integration checks prevent claiming completion.

Do not expand this work to the non-goals in DESIGN. The evidence above, rather than document checkboxes alone, determines completion.
