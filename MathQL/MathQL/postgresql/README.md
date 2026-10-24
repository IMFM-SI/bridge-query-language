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
