import MathQL.Compile
import MathQL.Database
import SQLite
import Lean.Data.Json

/-! Execution of a type-checked query against a SQLite connection, producing a
JSON array of result rows. Each output column is read at its declared type and
rendered to JSON; a NULL cell becomes JSON `null`. -/

namespace MathQL

/-- Read one output column at its declared type, as JSON; a NULL cell is `null`.
Lists and products are stored as JSON text and returned verbatim. -/
def decodeCell : Ty → SQLite.RowReader Lean.Json
  | .int => do
    let o : Option Int64 ← SQLite.RowReader.field
    return match o with | some i => Lean.toJson i.toInt | none => Lean.Json.null
  | .bool => do
    let o : Option Bool ← SQLite.RowReader.field
    return match o with | some b => Lean.toJson b | none => Lean.Json.null
  | .string => do
    let o : Option String ← SQLite.RowReader.field
    return match o with | some s => Lean.toJson s | none => Lean.Json.null
  | .list _ | .prod _ => do
    let o : Option String ← SQLite.RowReader.field
    match o with
    | none => return Lean.Json.null
    | some s =>
      match Lean.Json.parse s with
      | .ok j => return j
      | .error e => throw (IO.userError s!"expected JSON in a list or product column: {e}")

/-- Read one row's output columns, keyed by their aliases, in output order. -/
def rowObject (q : Query) : SQLite.RowReader Lean.Json := do
  let fields ← q.output.mapM fun (x, t, _) => do
    let v ← decodeCell t
    return (x.name, v)
  return Lean.Json.mkObj fields

/-- Step through every result row, decoding each into its output object. -/
partial def collectRows (stmt : SQLite.Stmt) (q : Query) (acc : Array Lean.Json) :
    IO (Array Lean.Json) := do
  if ← stmt.step then
    let row ← (rowObject q).run stmt
    collectRows stmt q (acc.push row)
  else
    return acc

/-- Run a type-checked query against an open SQLite connection, as a JSON array of rows. -/
def run (db : SQLite) (D : Database) (q : Query) : IO (Except String Lean.Json) := do
  match compileQuery D q with
  | .error e => return .error e
  | .ok sql =>
    let stmt ← db.prepare (toString sql)
    let rows ← collectRows stmt q #[]
    return .ok (Lean.Json.arr rows)

end MathQL
