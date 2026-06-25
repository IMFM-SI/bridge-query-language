# MathQL

MathQL is a query language for databases of mathematical objects. An agent (or
a human) asks mathematical questions about mathematical objects — graphs,
maniplexes, and more — and the engine compiles them to SQL against whatever
database holds those objects. The query language is defined in
[`LANGUAGE.md`](LANGUAGE.md); the design and goals are in [`PLAN.md`](PLAN.md);
[`docs/mathql-intro.md`](docs/mathql-intro.md) is a short introduction.

## Repository layout

```
.
├── LANGUAGE.md        the query language: syntax, types, typing
├── PLAN.md            design and implementation plan
├── docs/              a short introduction
├── MathQL/            the engine — a Lean package (parser, compiler, runner)
├── python/            database generation and the MCP server
├── data/              the databases and their descriptions
└── lean/              earlier Lean experiments with the typed core
```

## Prerequisites

- **elan** (the Lean toolchain manager). Lake fetches the pinned toolchain
  automatically; no separate Lean install is needed.
- A **C compiler** (clang or gcc) — the SQLite binding compiles a bundled copy
  of SQLite. On macOS, the Xcode Command Line Tools (`xcode-select --install`).
- **leansqlite**, cloned as a sibling of this repository at `../leansqlite`.
- For generating the small-graphs database: **nauty** (`geng`) and Python with
  **networkx**.
- For the MCP server: Python with the **mcp** package.

```
python3 -m venv .venv && source .venv/bin/activate
python -m pip install networkx mcp
```

## Building the engine

```
cd MathQL
lake build          # builds the `mathql` executable (and the test runner)
```

The first build fetches the Lean toolchain and compiles the SQLite
amalgamation, so it takes a few minutes; later builds are fast.

## Databases

The databases live in `data/` and are not checked into git.

- **`graphs-small.db`** — all graphs on up to 8 vertices, with invariants.
  Generate it from the repository root:

  ```
  python python/generate_graphs.py
  ```

  Schema and details: [`data/graphs-small-description.md`](data/graphs-small-description.md).

- **`sym-ob-small.db`** — regular rank-4 maniplexes (≈ 300 MB). Download from
  <https://www.andrej.com/tmp/sym-ob-small.db> into `data/`. Schema:
  [`data/sym-ob-small-description.md`](data/sym-ob-small-description.md).

## Running queries

A query is a comprehension over a domain of objects. Run it from the `MathQL/`
directory (the executable resolves `../data` relative to its working
directory):

```
cd MathQL
lake exe mathql '{ (g.num_vertices, g.num_edges) | g ∈ SmallGraphs, g.is_tree }'
lake exe mathql --count '{ g | g ∈ SmallGraphs, g.is_planar ∧ g.is_connected }'
lake exe mathql '{ m.schlafli_symbol | m ∈ Maniplexes, m.size = 8 ∧ m.orientable }'
```

The domain named in the query (`SmallGraphs`, `Maniplexes`) selects the
database; you never name a table or a file. UTF-8 operators (`∈ ∧ ∨ ¬ ≠ ≤ ≥`)
and their ASCII synonyms (`in && || ! != <= >=`) are both accepted.

`mathql describe` prints the JSON schema of every domain, and `mathql serve`
reads one query per line and writes one JSON result per line.

## MCP server

`python python/mcp_server.py` starts an MCP server that exposes MathQL to an AI
agent as two tools — `describe_schema` and `query` — forwarding to the compiled
`mathql` executable. Point an MCP client at that command (with the project's
virtual environment active).

## Tests

```
cd MathQL
lake exe test       # end-to-end checks against data/graphs-small.db
```

## The language

[`LANGUAGE.md`](LANGUAGE.md) gives the full language: its concrete syntax,
types, and a bidirectional typing judgement, and how it corresponds to the Lean
development.
