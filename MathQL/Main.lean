import SQLite

import MathQL.GraphsSmallDB
import MathQL.SymObSmallDB
import MathQL

/-! The `mathql` executable: a persistent process answering queries over stdin/stdout.

It opens the database once, then reads one JSON request per line and writes one
JSON response per line: `{"rows": …}` on success, `{"error": …}` on failure. This
is the transport the MCP server (`python/src/mathql_mcp`) speaks to. -/

open MathQL

/-- The names of the columns of `table`. -/
def columnNames (db : SQLite) (table : String) : IO (List String) := do
  let stmt ← db.prepare "SELECT name FROM pragma_table_info(?)"
  stmt.bindText 1 table
  let names ← (stmt.resultsAs String).toArray
  return names.toList

/-- A name is a safe alias when no table of `database` has a column of that name.
    `rowid`, `oid` and `_rowid_` name a column that `pragma_table_info` omits. -/
def safeAliasPredicate (db : SQLite) (database : Database) : IO (String → Bool) := do
  let columns ← database.domain.mapM fun (_, sch) => columnNames db sch.table
  let taken := ("rowid" :: "oid" :: "_rowid_" :: columns.flatten).map String.toLower
  return fun s => !taken.contains s.toLower

/-- Run one request `Json` and produce its response `Json`. -/
def handle (db : SQLite) (database : Database) (isSafeAlias : String → Bool)
    (j : Lean.Json) : IO Lean.Json := do
  match j.getObjVal? "describe" with
  | .ok _ => return database.describe
  | .error _ =>
    match Input.Query.fromJson j >>= checkQuery database with
    | .error e => return Lean.Json.mkObj [("error", Lean.Json.str e)]
    | .ok q =>
      match ← run db database isSafeAlias q with
      | .error e => return Lean.Json.mkObj [("error", Lean.Json.str e)]
      | .ok rows => return Lean.Json.mkObj [("rows", rows)]

/-- Read requests line by line until end of input, answering each on its own line. -/
partial def loop (db : SQLite) (database : Database) (isSafeAlias : String → Bool) :
    IO Unit := do
  let stdin ← IO.getStdin
  let line ← stdin.getLine
  if line.isEmpty then
    pure ()                                   -- end of input
  else
    let request := line.trimAscii.toString
    if request.isEmpty then
      loop db database isSafeAlias            -- blank line, skip
    else
      let response ← match Lean.Json.parse request with
        | .error e => pure (Lean.Json.mkObj [("error", Lean.Json.str s!"invalid JSON: {e}")])
        | .ok j => handle db database isSafeAlias j
      let stdout ← IO.getStdout
      stdout.putStrLn response.compress
      stdout.flush
      loop db database isSafeAlias

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
    let isSafeAlias ← safeAliasPredicate db database
    loop db database isSafeAlias
