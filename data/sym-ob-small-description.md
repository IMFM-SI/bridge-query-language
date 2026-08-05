# `sym-ob-small.db` — schema and contents

A SQLite database of regular rank-4 maniplexes together with their flag
graphs, skeleta, and canonical labelings. File size ≈ 298 MB.

The database can be downloaded from
<https://www.andrej.com/tmp/sym-ob-small.db>.

## What these objects are

Basic vocabulary about polytopes follows.

**Abstract polytopes.** Start with a cube. Its *faces*, in the broad
sense, are its 8 vertices, 12 edges, and 6 square facets, and we adjoin
two improper faces: the empty face and the whole cube. Order these by
inclusion: a vertex is below an edge when it is an endpoint, an edge below
a square when it bounds it, and the empty face sits below everything while
the whole cube sits above everything. This poset, forgetting all
coordinates and keeping only which face contains which, is the *abstract
polytope* of the cube. Its *rank* function records dimension: −1 for the
empty face, 0 for vertices, 1 for edges, 2 for squares, 3 for the cube
itself.

In general an *abstract polytope* of rank *n* is such a graded poset of
faces, with ranks running from −1 to *n*, that satisfies a few
combinatorial axioms:
unique least and greatest faces; every maximal chain has the same length
*n* + 2; the *diamond condition* — between a rank-(*i*−1) face and an
incident rank-(*i*+1) face lie exactly two rank-*i* faces; and some
further technical connectedness conditions.
For rank 3 this recovers the familiar notion of a *map* (see below).

**Flags.** A *flag* is a maximal chain in the face poset — one face of
each rank, all mutually incident; for the cube, a (vertex, edge, square,
cube) chain, and for a map a (vertex, edge, face) triple that all meet.
The diamond condition says each flag has, for every rank *i*, exactly one
neighbouring flag differing only in its rank-*i* element. This gives
*i*-adjacency involutions on the set of flags.

**Maniplexes.** A *maniplex* of rank *n* abstracts this structure
directly: a set of flags together with *n* fixed-point-free involutions
*r₀, …, rₙ₋₁* (the adjacencies), where non-consecutive involutions commute.
Rank-3 maniplexes are exactly *maps* — graphs embedded on a closed
surface so that cutting along the graph leaves a collection of disks, the
*faces* (vertices, edges, and faces being the ranks 0, 1, 2); the rank-4 maniplexes stored here are
the analogue one dimension up (think "3-dimensional maps", the
combinatorics of 4-polytopes and their relatives). A maniplex need not
come from an actual polytope — that is what the `polytopality` column
records (`Polytopal` vs. merely `Faithful`/`Unfaithful`).

**Connection group and flag graph.** The involutions *rᵢ* generate the
*connection (monodromy) group* acting on the flags. Encoding each *rᵢ* as
a permutation gives the `generators` column. The *flag graph* has the
flags as vertices and an *i*-coloured edge for each *i*-adjacency; it is a
properly edge-coloured, regular graph that determines the maniplex. The
*1-skeleton* is the ordinary vertex–edge graph of the underlying polytope,
and the *1-coskeleton* is that of its dual.

**Regularity and the Schläfli symbol.** Every maniplex here is *regular*:
its automorphism group acts simply transitively on flags, so the object is
maximally symmetric. The `schlafli_symbol`
`[p, q, r]` records the local type — the 2-faces are *p*-gons, the
vertex-figures *q*-gons, and so on — exactly as `{p, q, r}` does for the
classical regular 4-polytopes. Three entries means rank 4.

The database is a census of highly symmetric rank-4 combinatorial structures,
stored through the graphs (flag graph, skeleton, coskeleton) that encode them.

## Tables

### `graph`
Undirected graphs stored in `sparse6` encoding. Used for flag graphs,
1-skeleta, and 1-coskeleta of the maniplexes.

| column | type | notes |
| --- | --- | --- |
| `id` | INTEGER PK | |
| `graph_in_sparse6` | TEXT, unique | `sparse6` string |
| `order` | INTEGER | number of vertices |
| `size` | INTEGER | number of edges |
| `degree_sequence` | TEXT | JSON list of vertex degrees |

### `maniplex`
The central table: one row per regular rank-4 maniplex.

| column | type | notes |
| --- | --- | --- |
| `id` | INTEGER PK | |
| `size` | INTEGER | number of flags |
| `schlafli_symbol` | TEXT | e.g. `[4,8,8]` (always three entries → rank 4) |
| `generators` | TEXT | the connection-group generators as permutation lists |
| `orientable` | INTEGER | 0 / 1 |
| `polytopality` | TEXT | `Polytopal`, `Faithful`, or `Unfaithful` |
| `cl_flag_graph_id` | INTEGER FK → `canonicallabeling` | |
| `cl_fg_edge_coloring` | TEXT | edge coloring of the flag graph |
| `one_skeleton` | TEXT | |
| `cl_one_skeleton_id` | INTEGER FK → `canonicallabeling` | |
| `one_coskeleton` | TEXT | |
| `cl_one_coskeleton_id` | INTEGER FK → `canonicallabeling` | |
| `color_group` | TEXT | color-symmetry group as permutation lists |
| `symmetry_type` | TEXT | |

### `canonicallabeling`
A canonical vertex ordering of a graph, produced by a labeling tool with
fixed parameters.

| column | type | notes |
| --- | --- | --- |
| `id` | INTEGER PK | |
| `vertices_in_canonical_order` | TEXT | JSON permutation of vertices |
| `graph_in_sparse6_id` | INTEGER FK → `graph` | |
| `parameters_id` | INTEGER FK → `clparameters` | |

### `clparameters`
The labeling-tool configuration used to compute canonical labelings.

| column | type | notes |
| --- | --- | --- |
| `id` | INTEGER PK | |
| `software` | TEXT | |
| `version` | TEXT | |
| `prefix` / `suffix` | TEXT | tool invocation arguments |

### `graphexternalreference`
Cross-references from a graph to its identifier in an external census or
database.

| column | type | notes |
| --- | --- | --- |
| `id` | INTEGER PK | |
| `graph_id` | INTEGER FK → `graph` | |
| `source` | TEXT | external collection name |
| `id_source` | TEXT | identifier within that collection |

## Basic statistics

Row counts:

| table | rows |
| --- | --- |
| `graph` | 12 568 |
| `maniplex` | 32 634 |
| `canonicallabeling` | 34 411 |
| `graphexternalreference` | 348 |
| `clparameters` | 1 |

**Graphs.** Order ranges over 1–1000 vertices; size over 0–2000 edges.

**Maniplexes.** All 32 634 are rank 4 (every Schläfli symbol has three
entries) and have `symmetry_type = regular`. Flag count (`size`) ranges
8–1000, mean ≈ 618. Every maniplex has a 1-skeleton labeling.

- Orientability: 13 214 orientable, 19 420 non-orientable.
- Polytopality: 23 005 `Unfaithful`, 6 101 `Faithful`, 3 528 `Polytopal`.
- Most maniplexes have a trivial color group (`[]`, 27 290 rows); the rest
  carry small permutation color groups.
- Most common Schläfli symbols include `[8,8,4]`, `[4,8,8]`, `[4,12,4]`,
  `[8,12,4]`, `[4,12,8]`, and `[24,24,2]` (≈ 90–123 maniplexes each).

**Canonical labelings.** All computed with a single parameter set:
Traces 2.9.3, prefix `At c V=0`, suffix `x b q`.

**External references.** 348 rows pointing into four collections: `HoG`
(House of Graphs, 208), `Census4val2AT` (9), `Census4val` (66), and `C4`
(65).
