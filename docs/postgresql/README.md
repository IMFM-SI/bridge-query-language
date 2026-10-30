# PostgreSQL backend documentation

Status: proposed implementation, not completed PostgreSQL support. Baseline source observations were reviewed at commit `076d954`; verify them against the current checkout before editing code.

Read in this order:

1. [DESIGN.md](DESIGN.md): authoritative requirements and chosen interfaces.
2. [ARCHITECTURE.md](ARCHITECTURE.md): runtime flow, module ownership and import boundaries.
3. [IMPLEMENTATION.md](IMPLEMENTATION.md): buildable milestones and acceptance checks.
4. [DIFFERENCES.md](DIFFERENCES.md): concrete behavioral examples and verification evidence.

Requirement IDs in DESIGN are stable references for implementation and review. Current code defines baseline behavior; DESIGN defines required changes. DIFFERENCES supplies the expected outcomes for the examples referenced by DESIGN.

If implementation reveals a conflict or requires changing language behavior, explain the minimal example and proposed options to the user before proceeding with the affected work. Update DESIGN if the decision changes the requirements.

Paths are relative to the repository root unless stated otherwise. Work in `MathQL/`, the active Lean package. Read `README.md`, `LANGUAGE.md` and `docs/query-grammar.md` in the repository for existing usage and language context.

## Scope

PostgreSQL support is for the Lean implementation only. The in-repository MCP server (`python/src/mathql_mcp`) and the Python implementation in `../bridge-mcp` are out of scope: do not change them, and do not treat the new `describe` field or CLI options as requiring changes there. The importer under `python/postgresql/` (IMPORT-01) is in scope; it is setup tooling, not a query implementation.

## Environment

- `data/graphs-small.db` and `data/sym-ob-small.db` are downloaded manually and are not in the repository (`*.db` is gitignored). If they are missing, report that instead of treating dataset checks as passed.
- `MathQL/lakefile.lean` fetches leansqlite over SSH. On a machine without a GitHub SSH key, clone the revision pinned in `lake-manifest.json` over HTTPS into `MathQL/.lake/packages/leansqlite` rather than editing the lakefile.
- Pending decision: how PostgreSQL is provisioned for development and tests (most likely a container), including server version, role setup and whether live tests run in CI. Until this is recorded here, do not invent a provisioning setup; ask the user.
