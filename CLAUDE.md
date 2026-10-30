# MathQL (Lean)

Read `HANDOFF.md` first: it records how this repository relates to `../bridge-mcp` and what
work is decided.

## Active work: PostgreSQL backend

On branch `postgres-integration`. Start at `docs/postgresql/README.md`, which gives the
reading order and how to resolve conflicts with the design.

- Lean only. Do not change `python/src/mathql_mcp` or `../bridge-mcp` for this work.
- The current phase is defining the feature and its architecture in `docs/postgresql/`.
  How tests are laid out is deliberately deferred; do not design a test harness yet.
- How PostgreSQL is provisioned (likely a container) is not decided. Ask; do not invent one.

## Environment

- The Lean package is `MathQL/`; build with `cd MathQL && lake build`.
- `MathQL/lakefile.lean` fetches leansqlite over SSH. Without a GitHub SSH key, clone the
  revision pinned in `MathQL/lake-manifest.json` over HTTPS into
  `MathQL/.lake/packages/leansqlite`; do not edit the lakefile.
- `data/*.db` are downloaded manually and gitignored. If they are missing, say so rather
  than treating dataset checks as passed.
