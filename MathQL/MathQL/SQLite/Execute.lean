import MathQL.SQLite.Compile
import MathQL.Database
import SQLite
import Lean.Data.Json

/-! Execution of a type-checked query against a SQLite connection, producing the ordered
result rows. Each output column is read at its declared type and rendered to JSON; a NULL cell
becomes JSON `null`. Postprocessing is not done here; see `MathQL.Postprocess`. -/

namespace MathQL.SQLite

/-- Read one output column at its declared type, as JSON; a NULL cell is `null`.
Lists and products are stored as JSON text and returned verbatim. -/
def decodeCell : Ty → _root_.SQLite.RowReader Lean.Json
  | .int => do
    let o : Option Int64 ← _root_.SQLite.RowReader.field
    return match o with | some i => Lean.toJson i.toInt | none => Lean.Json.null
  | .bool => do
    let o : Option Bool ← _root_.SQLite.RowReader.field
    return match o with | some b => Lean.toJson b | none => Lean.Json.null
  | .string => do
    let o : Option String ← _root_.SQLite.RowReader.field
    return match o with | some s => Lean.toJson s | none => Lean.Json.null
  | .list _ | .prod _ => do
    let o : Option String ← _root_.SQLite.RowReader.field
    match o with
    | none => return Lean.Json.null
    | some s =>
      match Lean.Json.parse s with
      | .ok j => return j
      | .error e => throw (IO.userError s!"expected JSON in a list or product column: {e}")

/-- Read one row's output columns, keyed by their aliases, in output order. -/
def rowObject (cs : List (Ident × Ty × Expr)) : _root_.SQLite.RowReader (List (Ident × Lean.Json)) := do
  cs.mapM fun (x, t, _) => do
    let v ← decodeCell t
    return (x, v)

/-- Step through every result row, decoding each into its output columns in order. -/
partial def collectRows (stmt : _root_.SQLite.Stmt) (q : Query)
    (acc : Array (List (Ident × Lean.Json))) : IO (Array (List (Ident × Lean.Json))) := do
  if ← stmt.step then
    let row ← (rowObject q.output).run stmt
    collectRows stmt q (acc.push row)
  else
    return acc

/-- Compile a type-checked query with the registrations `R` and run it against an open SQLite
connection, giving the rows in order, each its output columns in order. -/
def execute (db : _root_.SQLite) (D : Database) (R : Registrations) (isSafeAlias : String → Bool)
    (q : Query) : IO (Except String (Array (List (Ident × Lean.Json)))) := do
  match compileQuery D R isSafeAlias q with
  | .error e => return .error e
  | .ok sql =>
    let stmt ← db.prepare (toString sql)
    return .ok (← collectRows stmt q #[])

end MathQL.SQLite
