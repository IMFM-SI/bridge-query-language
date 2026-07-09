import MathQL.GraphsSmallDB
import MathQL.SymObSmallDB
import SQLite

/-! The `mathql` executable: a persistent query engine driven over stdin/stdout.

It opens the database once, then reads one JSON request per line and writes one
JSON response per line: `{"rows": …}` on success, `{"error": …}` on failure. This
is the transport the Python MCP server (`python/src/mathql_mcp`) speaks to. -/

open MathQL

/-- Run one request `Json` and produce its response `Json`. -/
def handle (db : SQLite) (database : Database) (j : Lean.Json) : IO Lean.Json := do
  match j.getObjVal? "describe" with
  | .ok _ => return database.describe
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

/-- The known databases: each name with its `Database` and its default file path. -/
def databases : List (String × Database × String) :=
  [ ("graphs-small", GraphsSmallDB.database, "../data/graphs-small.db"),
    ("sym-ob-small", SymObSmallDB.database, "../data/sym-ob-small.db") ]

/-- Open the database (named by the first argument, its file path optionally
overridden by the second) and serve requests. -/
def main (args : List String) : IO Unit := do
  let name := (args[0]?).getD "graphs-small"
  match databases.find? (fun (n, _, _) => n == name) with
  | none =>
    IO.eprintln s!"unknown database '{name}'; available: \
      {", ".intercalate (databases.map (·.1))}"
  | some (_, database, defaultPath) =>
    let path := (args[1]?).getD defaultPath
    let db ← SQLite.openWith path .readonly
    loop db database
