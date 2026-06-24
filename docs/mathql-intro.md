# MathQL: asking mathematical questions of a database

## The problem

Mathematicians have built remarkable databases of objects: all small groups,
all small graphs, knots, lattices, regular maps, abstract polytopes. Each one
stores a collection of objects together with a pile of computed *invariants* —
for a graph, its chromatic number, girth, planarity; for a maniplex, its
Schläfli symbol, orientability, and so on.

These databases are wonderful and almost always awkward to query. The data
lives in SQL tables, CSV dumps, or bespoke file formats, and to ask a question
you must know the schema: which table, which column, how rows in one table
join to rows in another. That is a tax on a working mathematician, and it is a
serious obstacle for the use case we care about most — an **AI agent** that
wants to look something up while reasoning. We do not want the agent writing
`SELECT … JOIN … WHERE`. We want it to ask a mathematical question.

MathQL is a small query language for exactly that. Its guiding principle: **the
interface is mathematical, not relational.** You name a *domain* of objects and
talk about their *invariants*. Tables, columns, joins, and file formats stay on
our side of the fence.

## The idea

A MathQL query is a comprehension, the notation a mathematician already writes
on a whiteboard:

```
{ return-value  for  x in Domain  if  condition }
```

You pick a domain of objects, keep the ones satisfying a condition, and say
what to return. The condition and the returned value are ordinary expressions
built from the object's invariants — comparisons, boolean connectives,
arithmetic, tuples. Nothing about storage appears.

## A demo: small graphs

We have a database of all 13,598 graphs on up to eight vertices, each with two
dozen invariants. Here is the domain `SmallGraphs` in action — run through the
`mathql` command, which prints each answer as JSON.

Which vertex counts admit a complete graph? (Equivalently: connected graphs in
which every vertex is adjacent to all others.)

```
{ g.num_vertices for g in SmallGraphs if g.is_connected && g.min_degree == g.num_vertices - 1 }
→ 1, 2, 3, 4, 5, 6, 7, 8
```

There is exactly one complete graph on each vertex count — `K₁` through `K₈` —
and the query found all eight. Note `g.min_degree == g.num_vertices - 1`: an
invariant compared against an arithmetic expression in another invariant.

We can return the object itself, not just a number:

```
{ g for g in SmallGraphs if g.num_vertices == 3 && g.num_edges == 3 }
→ {"graph6": "Bw", "num_vertices": 3, "edges": [[0,1],[0,2],[1,2]]}
```

That is the triangle, rendered as an edge list. The query returned a *graph*,
and MathQL chose how to present it; the same object could be rendered in other
formats later.

A subtler example shows what happens when an invariant is *missing*. The radius
and diameter of a disconnected graph are undefined, so the database stores them
as null. Ask for graphs whose radius is below their diameter:

```
{ g for g in SmallGraphs if g.radius < g.diameter }   →  8,701 results
{ g for g in SmallGraphs if g.is_connected }          →  12,113 results
```

Every one of the 8,701 is connected — the 1,485 disconnected graphs drop out on
their own, because a comparison against a missing value is not true. MathQL is
robust to gaps in the data instead of crashing or lying about them.

## The same language, a different world

Now point the very same language at a completely different kind of object. The
domain `Maniplexes` is a database of 32,634 highly symmetric rank-4
combinatorial structures (the abstract-polytope cousins of maps on surfaces).
The query language does not change at all:

```
{ m for m in Maniplexes }                    →  32,634 results
{ m for m in Maniplexes if m.orientable }    →  13,214 results
```

We can pull out an invariant — here the Schläfli symbol, stored as a list:

```
{ m.schlafli_symbol for m in Maniplexes if m.size == 8 }
→ [2,2,2]  (and six more)
```

Or return a maniplex as an object, generators and all:

```
{ m for m in Maniplexes if m.size == 8 }
→ {"size": 8, "schlafli_symbol": [2,2,2], "orientable": true,
   "polytopality": "Unfaithful", "generators": [[1,2,4,3,6,5], …]}
```

The agent writing these queries never learns that graphs and maniplexes live in
different SQLite files with different schemas. It names a domain; we route the
query to the right database and translate it.

## Under the hood, briefly

A query is parsed, and the parts of its condition that can be expressed in SQL
are **translated to SQL**; anything that cannot is evaluated in Python over the
rows that come back. A per-database *schema descriptor* is the heart of the
system: it maps each mathematical invariant name to how that invariant is
computed — which column holds it, what codec decodes it (a stored `[4, 8, 8]`
text becomes a Python list), and, in time, what joins reach invariants that
live in a related table. Because the descriptor is the only thing tying a
domain to storage, a database need not even be a file on disk: one could be
generated on demand — say, by enumerating graphs with `nauty` and computing
invariants on the fly — behind the same mathematical interface.

## A subtlety we are careful about

Once you can follow relationships between objects, an obvious temptation is to
join *across* databases — "is this maniplex's 1-skeleton one of our small
graphs?" Here lies a trap. Two graph databases generally use different
encodings (one stores `graph6`, the other `sparse6`) and different *canonical
labelings* (produced by different tools), and their integer row ids are private
to each file. So "the same graph" cannot be matched by comparing stored strings
or ids. It requires canonicalizing both graphs to one shared form and comparing
*that*. MathQL therefore keeps every join inside a single database, where a
foreign key gives an unambiguous answer, and refuses to silently bridge two.

## Where we are, and what is next

The prototype is real and runs today: two databases, a parser, a
compile-to-SQL engine with a Python fallback, a command-line tool, a test
suite, and an MCP server that exposes MathQL as a tool an AI agent can call. It
is written in Python (so our machine-learning collaborators can read and extend
it), while a Lean development serves as the formal specification of the typed
language.

Next on the list:

- **Joins within a database**, so a query can reach an object's related objects
  — e.g. a maniplex's 1-skeleton and *its* invariants.
- **Three-valued logic** for missing data, letting a caller choose between
  "no false positives" and "no false negatives".

We would love your feedback — on the query syntax, on which invariants and
which databases would be most useful, and on whether this is the right shape
for the mathematical interface we want agents (and ourselves) to use.
