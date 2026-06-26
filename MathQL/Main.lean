import MathQL.GraphsSmallDB
import SQLite

/-! Demonstrate the whole MathQL pipeline against `data/graphs-small.db`: parse a
query string, type-check it against the database, execute it over the SQLite
connection, and print the JSON result. -/

/-- A sample query (JSON form): the three densest graphs on 5 vertices, ordered by
number of edges (descending). -/
def sampleQuery : Lean.Json :=
  json% {
    "domains":   [["g", "Graph"]],
    "output":    ["g.graph6", "g.num_vertices", "g.num_edges"],
    "condition": "g.num_vertices == 5",
    "order":     [["g.num_edges", "desc"]],
    "limit":     3
  }

open MathQL in
def main : IO Unit := do
  IO.println s!"query: {sampleQuery.compress}"
  let db ← SQLite.openWith "../data/graphs-small.db" .readonly
  match Input.Query.fromJson sampleQuery >>= checkQuery GraphsSmallDB.database.getContext with
  | .error e => IO.eprintln s!"compile error: {e}"
  | .ok q =>
    match ← run db GraphsSmallDB.database q with
    | .error e => IO.eprintln s!"execution error: {e}"
    | .ok json => IO.println json.pretty
