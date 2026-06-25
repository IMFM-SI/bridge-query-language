# MathQL: asking mathematical questions of a database

## The problem

Mathematicians have built remarkable databases of objects: all small groups,
all small graphs, knots, lattices, regular maps, abstract polytopes. Each
stores a collection of objects together with a pile of computed *invariants* —
for a graph, its chromatic number, girth, planarity; for a maniplex, its
Schläfli symbol and orientability.

These databases are wonderful and almost always awkward to query. The data
lives in SQL tables, CSV dumps, or bespoke formats, and to ask a question you
must know the schema: which table, which column, how rows in one table join to
rows in another. That is a tax on a working mathematician, and a real obstacle
for the use case we care about most — an **AI agent** that wants to look
something up while reasoning. We do not want the agent writing
`SELECT … JOIN … WHERE`. We want it to ask a mathematical question.

MathQL is a small query language for exactly that. Its guiding principle: **the
interface is mathematical, not relational.** You name a *domain* of objects and
talk about their *invariants*. Tables, columns, joins, and file formats stay on
our side of the fence.

## The idea

A MathQL query is a comprehension — the notation a mathematician already writes
on a whiteboard:

```
{ return-value | x ∈ Domain, condition }
```

You pick a domain of objects, keep the ones satisfying a condition, and say
what to return. The condition and the returned value are ordinary expressions
built from the object's invariants — comparisons, logical connectives,
arithmetic, tuples. Nothing about storage appears.

## A demo: small graphs

We have a database of all 13 598 graphs on up to eight vertices, each with two
dozen invariants. Here is the domain `SmallGraphs` through the `mathql`
command, which prints each answer as JSON.

Which vertex counts admit a complete graph — connected graphs in which every
vertex is adjacent to all others?

```
mathql '{ g.num_vertices | g ∈ SmallGraphs, g.is_connected ∧ g.min_degree = g.num_vertices - 1 }'
→ 1, 2, 3, 4, 5, 6, 7, 8
```

There is exactly one complete graph on each vertex count — `K₁` through `K₈` —
and the query found all eight. Note `g.min_degree = g.num_vertices - 1`: an
invariant compared against an arithmetic expression in another invariant.

We can return the object itself:

```
mathql '{ g | g ∈ SmallGraphs, g.num_vertices = 3 ∧ g.num_edges = 3 }'
→ {"graph6": "Bw", "degree_sequence": [2,2,2], "num_vertices": 3, "chromatic_number": 3, …}
```

That is the triangle, with all its stored invariants.

A subtler case: the radius and diameter of a disconnected graph are undefined,
so the database stores them as null — in the language, their type is
`Option Int`. Ask for graphs whose radius is below their diameter:

```
mathql --count '{ g | g ∈ SmallGraphs, g.radius < g.diameter }'   →  8701
```

Every one of the 8 701 is connected; the 1 485 disconnected graphs drop out on
their own, because a comparison against a missing value is not true. MathQL is
robust to gaps in the data rather than crashing or lying about them.

## The same language, a different world

Point the very same language at a completely different kind of object. The
domain `Maniplexes` holds 32 634 highly symmetric rank-4 combinatorial
structures (the abstract-polytope cousins of maps on surfaces). The language
does not change:

```
mathql --count '{ m | m ∈ Maniplexes, m.orientable }'                       →  13214
mathql --count '{ m | m ∈ Maniplexes, m.polytopality = "Polytopal" }'       →  3528
mathql '{ m.schlafli_symbol | m ∈ Maniplexes, m.size = 8 ∧ m.orientable }'  →  [2,2,2], …
```

The agent writing these queries never learns that graphs and maniplexes live in
different SQLite files with different schemas. It names a domain; we route the
query to the right database and translate it.

## How it works

A query is parsed, type-checked against the named domain's invariants, and
**compiled to a single SQL `SELECT`** — the condition becomes the `WHERE`
clause, the returned value becomes the selected columns. SQLite does the work;
there is no separate evaluation engine. A per-domain *schema descriptor* is the
heart of the system: it maps each mathematical invariant to the column that
holds it and the codec that decodes it (a stored `[2, 2, 2]` text becomes a
list), and it is the only thing tying a domain to storage. Because of that, a
database need not even be a file: one could be generated on demand behind the
same mathematical interface.

The engine is written in **Lean 4**, talking to SQLite through the
`leansqlite` bindings. Writing it in Lean is deliberate: the language is given
a precise type system and semantics, so the implementation and its
specification are one artifact, and the compilation to SQL can eventually be
*proved* correct. Python is kept only for what it is best at — generating the
sample databases, and hosting a thin MCP server that lets an AI agent call
MathQL as a tool.

## A subtlety we are careful about

Once you can follow relationships between objects, an obvious temptation is to
join *across* databases — "is this maniplex's 1-skeleton one of our small
graphs?" Here lies a trap. Two graph databases generally use different
encodings (one `graph6`, another `sparse6`) and different *canonical labelings*
(from different tools), and their integer row ids are private to each file. So
"the same graph" cannot be matched by comparing stored strings or ids; it
requires canonicalizing both graphs to one shared form and comparing that.
MathQL therefore keeps every join inside a single database, where a foreign key
gives an unambiguous answer, and refuses to silently bridge two.

## Where we are

The prototype runs today: a parser, a type checker, a compiler to SQL, a
command-line tool, a test suite, and an MCP endpoint, over two real databases.
Still ahead: joins to a related object's own invariants (a maniplex's
1-skeleton and *its* properties), and richer return shapes.

MathQL is being developed jointly by **Andrej Bauer** and **Claude** (Anthropic's
Claude Code) — a mathematician and an AI working the design out together, which
feels fitting for a tool meant to be used by both. We would love your feedback:
on the query syntax, on which invariants and databases would be most useful,
and on whether this is the right shape for the mathematical interface we want
agents — and ourselves — to use.
