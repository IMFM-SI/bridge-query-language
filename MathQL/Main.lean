import MathQL.GraphsSmallDB
import MathQL.SymObSmallDB
import MathQL.SQLite.Constants
import MathQL.SQLite.Functions
import MathQL.Backend

/-! The `mathql` executable: a persistent process answering queries over stdin/stdout.

It opens the database once, then reads one JSON request per line and writes one
JSON response per line: `{"rows": …}` on success, `{"error": …}` on failure. This
is the transport the MCP server (`python/src/mathql_mcp`) speaks to. -/

open MathQL

/-- Read requests line by line until end of input, answering each on its own line. -/
partial def loop (s : Session) : IO Unit := do
  let stdin ← IO.getStdin
  let line ← stdin.getLine
  if line.isEmpty then
    pure ()                                   -- end of input
  else
    let request := line.trimAscii.toString
    if request.isEmpty then
      loop s                                  -- blank line, skip
    else
      let response ← match Lean.Json.parse request with
        | .error e => pure (Lean.Json.mkObj [("error", Lean.Json.str s!"invalid JSON: {e}")])
        | .ok j => s.handle j
      let stdout ← IO.getStdout
      stdout.putStrLn response.compress
      stdout.flush
      loop s

/-- The known datasets: each name with its `Database`, its SQLite registrations, and its
default SQLite file path. -/
def databases : List (String × Database × SQLite.Registrations × String) :=
  [ ("graphs-small", GraphsSmallDB.database,
      { const := SQLite.Constants.graphsSmall, function := SQLite.Functions.graphsSmall },
      "../data/graphs-small.db"),
    ("sym-ob-small", SymObSmallDB.database,
      { const := SQLite.Constants.symObSmall, function := SQLite.Functions.symObSmall },
      "../data/sym-ob-small.db") ]

/-- Open the dataset (named by the first argument, its file path optionally
overridden by the second) and serve requests. -/
def main (args : List String) : IO Unit := do
  let name := (args[0]?).getD "graphs-small"
  match databases.find? (fun (n, _) => n == name) with
  | none =>
    IO.eprintln s!"unknown database '{name}'; available: \
      {", ".intercalate (databases.map (·.1))}"
  | some (_, database, registrations, defaultPath) =>
    let path := (args[1]?).getD defaultPath
    loop (← Session.openSQLite path database registrations)
