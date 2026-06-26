import MathQL.GraphsSmallDB
import SQLite

/-! Demonstrate the whole MathQL pipeline against `data/graphs-small.db`: parse a
query string, type-check it against the database, execute it over the SQLite
connection, and print the JSON result. -/

/-- A sample query: the graphs on 5 vertices that are trees, with a few
invariants in the output. -/
def sampleQuery : String :=
  "{ g.graph6, g.num_vertices, g.num_edges, g.degree_sequence | " ++
    "g ∈ Graph, g.num_vertices == 5 ∧ g.is_tree }"

open MathQL in
def main : IO Unit := do
  IO.println s!"query: {sampleQuery}"
  let db ← SQLite.openWith "../data/graphs-small.db" .readonly
  match Parsing.parse sampleQuery >>= checkQuery GraphsSmallDB.database.getContext with
  | .error e => IO.eprintln s!"compile error: {e}"
  | .ok q =>
    match ← run db GraphsSmallDB.database q with
    | .error e => IO.eprintln s!"execution error: {e}"
    | .ok json => IO.println json.pretty
