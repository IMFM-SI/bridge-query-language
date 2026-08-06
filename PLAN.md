# A query language for databases of mathematical objects

## Purpose

We are designing a query language for databases of mathematical objects.
Its primary users are AI agents, which will reach the databases through MCP
by issuing queries in this language; humans should be able to write it too.

There will be many databases. Some live locally, some sit behind a network,
and some exist only while a query runs — we may one day expose a database
that a tool *generates on the fly* (for example, enumerating graphs with
nauty and computing their invariants on demand). The query language is the
single interface that unifies all of them; it applies alike to stored and to
generated databases.

## The interface is mathematical

This is the governing principle, and we hold to it throughout: **the interface
presents mathematics, not a database.** An agent queries *mathematical
objects* by their *mathematical invariants*. It works with domains, objects,
and invariants alone; tables, columns, and joins stay on our side of the
interface.

Concretely, the agent works against a **domain of objects** — `SmallGraphs`,
`FiniteGroups`, `Maniplexes` — and refers to an object's invariants by their
mathematical names (`num_vertices`, `chromatic_number`, `is_planar`). How a
domain maps onto one or more tables, which joins compute a given invariant,
which columns to read, and what to render — all of that is *our* job, hidden
behind the interface. The agent asks a mathematical question; we compile it.

## What a query looks like

A query is a comprehension over a domain. Its filter and its returned value
are both **terms** in a small typed language built from the objects'
invariants:

```
{ return-term for g in Domain if condition }
```

Some examples in the provisional concrete syntax follow.

Connected non-planar graphs on at most 7 vertices, returning each graph
together with its chromatic number:

```
{ (g, g.chromatic_number) for g in SmallGraphs if g.is_connected && !g.is_planar }
```

Graphs whose radius is strictly less than their diameter, returning the degree
sequence — a comparison may relate two invariants:

```
{ g.degree_sequence for g in SmallGraphs if g.radius < g.diameter }
```

Regular graphs whose girth exceeds twice the chromatic number:

```
{ g for g in SmallGraphs if g.is_regular && g.girth > 2 * g.chromatic_number }
```

A few points the examples make:

- **The returned value is a term.** It may be the object itself (`g`, rendered
  in some representation — adjacency list, edge list, graph6), a single
  invariant, a derived quantity, or a tuple of these.
- **Conditions are general boolean expressions** over comparisons of terms,
  including invariant-to-invariant comparisons and arithmetic.
- A condition is built from invariants; the object itself may also be
  *returned* and rendered.

Ordering and limiting the results are not part of the query itself. They form a
separate layer that wraps a query, to be introduced later with its own sort
terms and a result bound.

An invariant can itself be a structured object with its own invariants, which
is how relationships between domains appear mathematically — e.g. a maniplex's
one-skeleton is a graph. Orientable maniplexes whose one-skeleton is bipartite:

```
{ m for m in Maniplexes if m.orientable && m.skeleton.is_bipartite }
```

The agent writes `m.skeleton.is_bipartite`; we discover that this needs a join
from the maniplex table to the graph table along a foreign key.

## Typing

Every query is well-typed; the type system stays simple, with a handful of ground
types (integers, booleans, strings, and structured values such as
lists or polynomials carried as JSON), products for tuples, comparison and
arithmetic operations over them. Ill-typed queries — comparing a boolean to an
integer, naming an unknown invariant — are rejected with a readable error the
agent can act on.

## Missing values

A possibly-absent invariant keeps its scalar type and may be absent for a given
object, stored as a `NULL` column. A query observes absence with `defined e` and
`undefined e`. See [`LANGUAGE.md`](LANGUAGE.md).

## What the compiler does

Everything relational lives here, downstream of the mathematical terms. From
the set of invariants the terms mention, the compiler:

- discovers which tables or views hold them and assembles the necessary joins;
- **translates** the whole query into SQL — the condition into a `WHERE` clause,
  the returned term into selected columns, the aggregates into SQL aggregate
  functions;
- renders the resulting objects in the chosen representation.

The condition, the output and the order have a SQL image and are evaluated by the
database. The postprocess entries are evaluated over the returned rows, outside the
database.

## The schema descriptor

A database is described in a standard way — a schema descriptor — read when a
query is compiled. The descriptor maps each **mathematical invariant name** to
how that invariant is *computed*: which table and column hold it, what join path
reaches it, and what codec decodes the stored value (e.g. JSON text → a list).
It also declares
the **representations** in which an object may be rendered for output. The
compiler reads this map to turn a term over invariant names into a relational
plan.

## Delivery

Parsing, type-checking, SQL translation and rendering are independent of how
queries arrive. We will exercise them first behind a plain command-line interface,
then wrap them in an MCP server that
exposes two tools: `query`, taking a query and returning rendered objects, and
`describe_schema`, returning a domain's objects, invariants with their types,
and available representations, so an agent can learn what it may ask before it
asks. MCP is then a thin adapter over the `mathql` executable.

## Implementation

MathQL is implemented in **Lean**; the full language is defined in
[`LANGUAGE.md`](LANGUAGE.md). **Python** generates the databases (`nauty` +
`networkx`) and hosts a thin MCP server that forwards to the Lean executable.
SQLite is reached through the **leansqlite** FFI binding; the project's Lean
toolchain is conformed to leansqlite's.

Architecture:

- **Lean executable `mathql`** — parse → elaborate to `Tm` →
  compile to SQL → run via leansqlite → decode and render. Two modes: a one-shot
  CLI (`mathql "<query>"`) and a serve mode that
  reads queries and writes JSON for the MCP server to drive.
- **Python** — `generate_graphs.py` (unchanged) and an MCP server that spawns
  the Lean executable in serve mode and forwards `query` / `describe_schema`.
- **leansqlite** — the one new dependency.

Steps (each a commit; carried out after this file is reviewed):

0. **(needs you)** Provide the following: a fork or repository URL of leansqlite
   to depend on, and confirmation that I may add it to the
   lakefile and move the Lean toolchain to match it. Confirm both databases are
   present under `data/` (`graphs-small.db` generated, `sym-ob-small.db`
   downloaded). Note anything else I will need (GAP, credentials, …).

1. **Lake skeleton** — a new standalone `MathQL/` package (toolchain
   `v4.32.0-rc1`, matching leansqlite; no mathlib) with a library and
   executable depending on leansqlite (`../leansqlite`) and `Cli`; verify a
   trivial `SELECT 1` round-trips through leansqlite.

2. **Concrete syntax and elaborator** — the syntax of `LANGUAGE.md` via Lean
   metaprogramming (`declare_syntax_cat` + `elab`), bidirectionally elaborating
   into the package's typed core `Tm`, with positioned type errors.

3. **Schema and realization** — represent each domain's record signature and
   its realization (table, per-field column and codec, enum constructor⇄value
   maps); declare `SmallGraphs` and `Maniplexes`.

4. **Compiler** — `Tm` / query → SQL with bound parameters: the condition to a
   `WHERE` clause, the returned term to selected columns.

5. **Execution** — run the SQL through leansqlite, decode rows by codec, and render
   the resulting objects.

6. **CLI and serve mode** — `mathql "<query>"` and the protocol the MCP server
   drives.

7. **Tests and examples** — elaborator, compiler, and end-to-end queries against
   a small fixture and against `graphs-small.db`.

8. **Python MCP server** — forward `query` / `describe_schema` to the Lean
   serve mode (generation stays in Python).

Definitions/prelude and the list aggregates are deferred to a later stage.

Verification throughout: build with `lake`, run the `LANGUAGE.md` example
queries against `data/graphs-small.db`, and check counts against known answers
(1, 2, 4, 11, 34, 156, 1044, 12346 graphs by vertex count; 48 trees; K₈ with
28 edges; 13 214 orientable maniplexes), alongside the ported test suite.
