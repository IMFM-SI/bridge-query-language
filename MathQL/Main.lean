import SQLite

open SQLite

def main : IO Unit := do
  let db ← SQLite.open ":memory:"
  let stmt ← db.prepare "SELECT 1 + 1"
  if ← stmt.step then
    IO.println s!"1 + 1 = {← stmt.columnInt64 0}"
  else
    IO.println "no row"
