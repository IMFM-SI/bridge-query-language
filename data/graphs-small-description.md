# `graphs-small.db` — schema and contents

A SQLite database of all non-isomorphic simple graphs on up to 8 vertices,
each annotated with a selection of graph invariants. One table, 13 598 rows,
≈ 944 KB. Built as a small, schema-controlled corpus for exercising the query
language.

## How to generate it

The database is produced by `python/generate_graphs.py`. It requires:

- **nauty** (for `geng`, the non-isomorphic graph generator) — `brew install nauty`;
- **networkx** (for the invariants) — `pip install networkx`.

Then, from the repository root:

```
python python/generate_graphs.py        # all graphs on up to 8 vertices
python python/generate_graphs.py 6      # up to 6 vertices instead
```

The script runs `geng n` for n = 1 … N, builds each graph in networkx,
computes the invariants, and writes them to `data/graphs-small.db`. It
**refuses to overwrite** an existing database — delete the file first to
regenerate. The set of invariants is the `INVARIANTS` list in the script; the
table schema is derived from it, so adding or removing a column is a one-line
edit.

## Table `graph`

| column | type | meaning |
| --- | --- | --- |
| `id` | INTEGER PK | |
| `graph6` | TEXT | the graph in `graph6` encoding (nauty's canonical form) |
| `num_vertices` | INTEGER | order |
| `num_edges` | INTEGER | size |
| `degree_sequence` | TEXT | JSON list of degrees, sorted descending |
| `min_degree` / `max_degree` | INTEGER | |
| `is_regular` | INTEGER | 0 / 1 |
| `num_components` | INTEGER | number of connected components |
| `is_connected` | INTEGER | 0 / 1 |
| `diameter` | INTEGER | NULL when disconnected |
| `radius` | INTEGER | NULL when disconnected |
| `girth` | INTEGER | length of a shortest cycle; NULL when acyclic |
| `is_tree` | INTEGER | 0 / 1 |
| `is_forest` | INTEGER | 0 / 1 |
| `is_bipartite` | INTEGER | 0 / 1 |
| `is_planar` | INTEGER | 0 / 1 |
| `is_eulerian` | INTEGER | 0 / 1 |
| `num_triangles` | INTEGER | number of 3-cliques |
| `clique_number` | INTEGER | size of a largest clique |
| `independence_number` | INTEGER | size of a largest independent set |
| `chromatic_number` | INTEGER | exact chromatic number |
| `automorphism_count` | INTEGER | order of the automorphism group |

Boolean-valued invariants are stored as `0`/`1` integers. `diameter`,
`radius`, and `girth` are `NULL` exactly when the invariant is undefined for
that graph.
