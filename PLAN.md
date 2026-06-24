# A query language for databases of mathematical objects

## Purpose

We are designing a query language for databases of mathematical objects.
Its primary users are AI agents, which will reach the databases through MCP
by issuing queries in this language; humans should be able to write it too.

There will be many databases. Some live locally, some sit behind a network,
and some need not be stored anywhere at all — we may one day expose a database
that a tool *generates on the fly* (for example, enumerating graphs with
nauty and computing their invariants on demand). The query language is the
single interface that unifies all of them; nothing in it assumes that a query
hits a stored table.

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

Ordering and limiting the results are deliberately left out of the query
itself: they shape the result stream rather than select objects, so they
belong to a separate layer that wraps a query. We can introduce that layer
later, with its own sort terms and a result bound, without changing the query
language.

An invariant can itself be a structured object with its own invariants, which
is how relationships between domains appear mathematically — e.g. a maniplex's
one-skeleton is a graph. Orientable maniplexes whose one-skeleton is bipartite:

```
{ m for m in Maniplexes if m.orientable && m.skeleton.is_bipartite }
```

The agent writes `m.skeleton.is_bipartite`; we discover that this needs a join
from the maniplex table to the graph table along a foreign key.

## Typing

Every query is well-typed, but the type system stays simple: a handful of
ground types (integers, booleans, strings, and structured values such as
lists or polynomials carried as JSON), products for tuples, comparison and
arithmetic operations over them. Ill-typed queries — comparing a boolean to an
integer, naming an unknown invariant — are rejected with a readable error the
agent can act on.

## Missing values

Invariants may be **missing**: a value too hard to compute for a particular
object is simply absent. The language must stay robust in their presence.

- **First prototypes use ordinary two-valued logic** and may ignore the
  subtlety, treating a query over a missing value conservatively.
- **The principled treatment is Kleene three-valued logic**: each atom is
  `true`, `false`, or `unknown` (when an invariant it mentions is missing). We
  evaluate the whole boolean structure in three values and let the user
  collapse `unknown` at the very end with one chosen policy — *sound* (keep
  only `true`; no false positives) or *complete* (keep `true` or `unknown`; no
  false negatives). Collapsing only at the end is what keeps negation honest:
  substituting `false` for a missing atom up front would make `!missing`
  become `true` and quietly corrupt the answer.

## What the compiler does

Everything relational lives here, downstream of the mathematical terms. From
the set of invariants the terms mention, the compiler:

- discovers which tables or views hold them and assembles the necessary joins;
- **translates** the part of the condition it can into SQL, and selects the
  underlying columns needed to compute the return term;
- evaluates in Python whatever does not translate — a *residual* filter — over
  the rows the database returns;
- renders the resulting objects in the chosen representation.

When a condition cannot be fully translated, the compiler may translate an
**over-approximation** to SQL (one that returns a superset) and apply the
residual filter afterwards. The first prototypes need not do this; they may
fetch a generous superset and filter in Python.

## The schema descriptor

A database is described in a standard way — for the Python prototype, a Python
class or module — that the query language consumes. The descriptor maps each
**mathematical invariant name** to how that invariant is *computed*: which
table and column hold it, what join path reaches it, and what codec decodes the
stored value (e.g. JSON text → a Python list or polynomial). It also declares
the **representations** in which an object may be rendered for output. The
compiler reads this map to turn a term over invariant names into a relational
plan.

## Delivery

The engine — parser, type-checker, SQL translation, residual evaluation,
rendering — is independent of how queries arrive. We will exercise it first
behind a plain command-line interface, then wrap it in an MCP server that
exposes two tools: `query`, taking a query and returning rendered objects, and
`describe_schema`, returning a domain's objects, invariants with their types,
and available representations, so an agent can learn what it may ask before it
asks. MCP is then a thin adapter over the engine.

## Implementation

We implement the engine in **Lean**, so that the implementation *is* the
specification: the elaborator produces the typed term `Tm`, the interpreter is
`Tm.interpret`, and the SQL compilation can eventually be proved sound against
`Query.interpret`. The full language is defined in [`LANGUAGE.md`](LANGUAGE.md).
**Python** is kept only for what it is best at — generating databases
(`nauty` + `networkx`) and hosting a thin MCP server that forwards to the Lean
executable. SQLite is reached through the **leansqlite** FFI binding, which
bundles the SQLite amalgamation and supports bound parameters; the project's
Lean toolchain is conformed to whatever leansqlite requires.

Architecture:

- **Lean executable `mathql`** — the engine: parse → elaborate to `Tm` →
  compile to SQL → run via leansqlite → decode, apply the residual filter,
  render. Two modes: a one-shot CLI (`mathql "<query>"`) and a serve mode that
  reads queries and writes JSON for the MCP server to drive.
- **Python** — `generate_graphs.py` (unchanged) and an MCP server that spawns
  the Lean executable in serve mode and forwards `query` / `describe_schema`.
- **leansqlite** — the one new dependency.

Steps (each a commit; carried out after this file is reviewed):

0. **(needs you)** Provide what I cannot fetch myself: a fork or repository URL
   of leansqlite to depend on, and confirmation that I may add it to the
   lakefile and move the Lean toolchain to match it. Confirm both databases are
   present under `data/` (`graphs-small.db` generated, `sym-ob-small.db`
   downloaded). Note anything else I will need (GAP, credentials, …).

1. **Lake skeleton** — extend the existing `lean/` project with a `mathql`
   library and executable depending on leansqlite and `Cli`, toolchain
   conformed; verify a trivial `SELECT 1` round-trips through leansqlite.

2. **Concrete syntax and elaborator** — the syntax of `LANGUAGE.md` via Lean
   metaprogramming (`declare_syntax_cat` + `elab`, building on `DSL.lean`),
   bidirectionally elaborating into the `Tm` of `Core.lean`, with positioned
   type errors.

3. **Schema and realization** — represent each domain's record signature and
   its realization (table, per-field column and codec, enum constructor⇄value
   maps); declare `SmallGraphs` and `Maniplexes`.

4. **Compiler** — `Tm` / query → SQL with bound parameters; whatever does not
   translate becomes a residual evaluated in Lean.

5. **Engine** — run the SQL through leansqlite, decode rows by codec, apply the
   residual, evaluate the returned term, render objects.

6. **CLI and serve mode** — `mathql "<query>"` and the protocol the MCP server
   drives.

7. **Prelude** — `count`, `sum`, `max`, … as definitions over `fold`.

8. **Tests and examples** — port the Python suite: elaborator, compiler, and
   end-to-end queries against a small fixture and against `graphs-small.db`.

9. **Python MCP server** — forward `query` / `describe_schema` to the Lean
   serve mode; retire the Python engine once the Lean engine is at parity
   (generation stays in Python).

Verification throughout: build with `lake`, run the `LANGUAGE.md` example
queries against `data/graphs-small.db`, and check counts against known answers
(1, 2, 4, 11, 34, 156, 1044, 12346 graphs by vertex count; 48 trees; K₈ with
28 edges; 13 214 orientable maniplexes), alongside the ported test suite.
