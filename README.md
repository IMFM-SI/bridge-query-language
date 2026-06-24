# MathQL

MathQL is a query language for databases of mathematical objects. An agent (or
a human) asks mathematical questions about mathematical objects — graphs,
maniplexes, and more — and the engine compiles them against whatever database
holds those objects. See [`PLAN.md`](PLAN.md) for the design and goals.

## Repository layout

```
.
├── PLAN.md            design of the query language
├── data/              the databases and their descriptions
├── python/            the Python prototype (engine, database generators)
└── lean/              the Lean formalisation (formal spec of the typed language)
```

## Prerequisites

- **Python 3.10 or newer** (developed on 3.14).
- **nauty**, for the `geng` graph generator, used to build the small-graph
  database:
  - macOS: `brew install nauty`
  - Debian/Ubuntu: `sudo apt install nauty` — the generator may be installed as
    `geng` or as `nauty-geng`; if it is the latter, set the `GENG` constant at
    the top of `python/generate_graphs.py` accordingly.

SQLite needs no installation — it comes with Python's standard library.

## Setup

Create and activate a virtual environment, then install the project (with its
development extras) in editable mode:

```
python3 -m venv .venv
source .venv/bin/activate          # bash / zsh;  Windows: .venv\Scripts\activate
python -m pip install --upgrade pip
python -m pip install -e ".[dev]"
```

This installs the `mathql` package, its dependencies (`lark` for parsing,
`networkx` for graph invariants, `mcp` for the server adapter), and the
development tools (`mypy`, `pytest`, `hypothesis`). The dependencies are
declared in [`pyproject.toml`](pyproject.toml).

Activate the environment (`source .venv/bin/activate`) in every new shell
before working on the project.

## Databases

The databases live in `data/` and are not checked into git; you produce them
locally.

- **`graphs-small.db`** — all non-isomorphic graphs on up to 8 vertices, with a
  selection of invariants. Generate it with:

  ```
  python python/generate_graphs.py            # up to 8 vertices
  python python/generate_graphs.py 6          # up to 6 vertices instead
  ```

  The script writes `data/graphs-small.db` and refuses to overwrite an existing
  file — delete it first to regenerate. Details and the full schema are in
  [`data/graphs-small-description.md`](data/graphs-small-description.md).

- **`sym-ob-small.db`** — regular rank-4 maniplexes (≈ 300 MB). Download it from
  <https://www.andrej.com/tmp/sym-ob-small.db> into `data/`. Its schema and
  contents are described in
  [`data/sym-ob-small-description.md`](data/sym-ob-small-description.md).

## Checking your setup

With the environment active:

```
geng 3                                        # prints the 4 graphs on 3 vertices
python -c "import mathql, networkx, lark; print('imports ok')"
python python/generate_graphs.py 5            # builds data/graphs-small.db (if absent)
sqlite3 data/graphs-small.db "SELECT num_vertices, COUNT(*) FROM graph GROUP BY num_vertices;"
```

The last query should report 1, 2, 4, 11, 34 graphs for 1 … 5 vertices.

## Running queries

A query is a comprehension over a domain of objects. The `mathql` command runs
one against the small-graphs database and prints each result as JSON:

```
mathql "{ (g.num_vertices, g.num_edges) for g in SmallGraphs if g.is_tree }"
mathql --count "{ g for g in SmallGraphs if g.is_planar && g.is_connected }"
mathql --limit 3 "{ g for g in SmallGraphs if g.num_vertices == 4 && g.is_regular }"
mathql --count '{ m for m in Maniplexes if m.orientable && m.polytopality == "Polytopal" }'
```

The domain named in the query (`SmallGraphs`, `Maniplexes`) selects the
database; you never name a table or a file.

`python/examples.py` runs a selection of queries with their result counts:

```
python python/examples.py
```

## MCP server

`mathql-mcp` starts an MCP server (stdio transport) so an AI agent can use
MathQL as a tool. It exposes two tools:

- `describe_schema` — the domains available and the invariants each provides,
  so a query can be written without knowing any storage details;
- `query` — run a MathQL query and return its results.

Point an MCP client at the `mathql-mcp` command (the one in the project's
virtual environment), for example with a client configuration entry:

```json
{ "command": "/path/to/.venv/bin/mathql-mcp" }
```

## Development

```
mypy python/mathql                            # type-check the engine
pytest                                        # run the test suite
```

The engine is a first prototype: parsing, SQL compilation, and execution work,
while the type-checking phase is currently a stub that accepts every query.

## The Lean formalisation

The `lean/` directory holds the formal specification of the typed query
language. It has its own toolchain and build instructions — see
[`lean/README.md`](lean/README.md).
