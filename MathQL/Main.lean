import MathQL.GraphsSmallDB
import SQLite

/-! The `mathql` executable: a persistent query engine driven over stdin/stdout.

It opens the database once, then reads one JSON request per line and writes one
JSON response per line: `{"rows": …}` on success, `{"error": …}` on failure. This
is the transport the Python MCP server (`python/mathql.py`) speaks to. -/

open MathQL

/-- Run one request `Json` and produce its response `Json`. -/
def handle (db : SQLite) (database : Database) (j : Lean.Json) : IO Lean.Json := do
  match j.getObjVal? "describe" with
  | .ok _ => return database.schema
  | .error _ =>
    match Input.Query.fromJson j >>= checkQuery database.getContext with
    | .error e => return Lean.Json.mkObj [("error", Lean.Json.str e)]
    | .ok q =>
      match ← run db database q with
      | .error e => return Lean.Json.mkObj [("error", Lean.Json.str e)]
      | .ok rows => return Lean.Json.mkObj [("rows", rows)]

/-- Read requests line by line until end of input, answering each on its own line. -/
partial def loop (db : SQLite) (database : Database) : IO Unit := do
  let line ← (← IO.getStdin).getLine
  if line.isEmpty then
    pure ()                                   -- end of input
  else
    let request := line.trimAscii.toString
    if request.isEmpty then
      loop db database                        -- blank line, skip
    else
      let response ← match Lean.Json.parse request with
        | .error e => pure (Lean.Json.mkObj [("error", Lean.Json.str s!"invalid JSON: {e}")])
        | .ok j => handle db database j
      let stdout ← IO.getStdout
      stdout.putStrLn response.compress
      stdout.flush
      loop db database

/-- Open the database (path from the first argument, defaulting to the bundled
`graphs-small.db`) and serve requests. -/
def main (args : List String) : IO Unit := do
  let dbPath := args.head?.getD "../data/graphs-small.db"
  let db ← SQLite.openWith dbPath .readonly
  loop db GraphsSmallDB.database
