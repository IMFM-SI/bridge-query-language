import SQLite
-- import MathQL.Compile
-- import MathQL.Databases
-- import MathQL.Parser

/-! Running a query: compile to SQL, execute through leansqlite, and read each
row back into a `Value`. -/

namespace MathQL

open SQLite


/-- Read this plan's value from the current row, starting at column `col`
    (0-indexed); returns the value and the next free column index. -/
private partial def Plan.read (stmt : SQLite.Stmt) : Plan → Int32 → IO (Value × Int32)
  | .scalar _ _ kind, col => do
    return (← decodeColumn kind stmt col, col + 1)
  | .object attrs, col => do
    let mut fields := #[]
    let mut i := col
    for a in attrs do
      fields := fields.push (a.name, ← decodeColumn a.kind stmt i)
      i := i + 1
    return (Value.obj fields.toList, i)
  | .tuple parts, col => do
    let mut vals := #[]
    let mut i := col
    for p in parts do
      let (v, i') ← Plan.read stmt p i
      vals := vals.push v
      i := i'
    return (Value.list vals.toList, i)

/-- Compile and run query `q` against database `db`. -/
def runOn (db : Database) (q : Query) : IO (Except String (List Value)) := do
  match compileQuery db q with
  | .error e => return .error e
  | .ok (_, c) =>
    let conn ← SQLite.openWith db.path OpenFlags.readonly
    let stmt ← conn.prepare c.sql
    let mut idx : Int32 := 1
    for p in c.params do
      bindParam stmt idx p
      idx := idx + 1
    let mut results := #[]
    repeat
      if ← stmt.step then
        results := results.push (← Plan.read stmt c.plan 0).1
      else break
    return .ok results.toList

/-- Parse, route to the database providing the named domain, and run. -/
def run (queryText : String) : IO (Except String (List Value)) := do
  match Parser.parse queryText with
  | .error e => return .error e
  | .ok q =>
    match databases.find? (fun db => (db.domain? q.domain).isSome) with
    | none => return .error s!"unknown domain '{q.domain}'"
    | some db => runOn db q

end MathQL
