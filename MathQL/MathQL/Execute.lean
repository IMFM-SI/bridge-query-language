import MathQL.Compile
import MathQL.Database
import SQLite
import Lean.Data.Json

/-! Execution of a type-checked query against a SQLite connection, producing a
JSON array of result rows. -/

namespace MathQL

/-- Read one row's requested output values, keyed by `(variable, label?)`. Every bound
variable is decoded in turn (the column cursor threads across the join), but only the
entries named in `q.output` are rendered: the whole object (`none`, via `toJson`) or a
single field (`some l`). -/
def rowFields (q : Query) (vars : List (Ident × Domain)) :
    SQLite.RowReader (List ((Ident × Option Label) × Lean.Json)) := do
  let perVar ← vars.mapM fun (x, dom) => do
    let o ← dom.decode
    return q.output.filterMap fun (y, ol) =>
      if y == x then
        match ol with
        | none   => some ((x, none), dom.toJson o)
        | some l => (dom.outputField.lookup l).map fun f => ((x, some l), f o)
      else none
  return perVar.flatten

/-- Assemble a row's JSON object in the query's output order. A bare variable
(`none`) is keyed by the variable name; a field by `variable.label`. -/
def rowObject (q : Query) (fields : List ((Ident × Option Label) × Lean.Json)) : Lean.Json :=
  Lean.Json.mkObj <| q.output.map fun (x, ol) =>
    let key := match ol with
      | none => x.name
      | some l => s!"{x.name}.{l.name}"
    (key, (fields.lookup (x, ol)).getD Lean.Json.null)

/-- Step through every result row, decoding each into its output object. -/
partial def collectRows (stmt : SQLite.Stmt) (vars : List (Ident × Domain)) (q : Query)
    (acc : Array Lean.Json) : IO (Array Lean.Json) := do
  if ← stmt.step then
    let fields ← (rowFields q vars).run stmt
    collectRows stmt vars q (acc.push (rowObject q fields))
  else
    return acc

/-- Run a type-checked query against an open SQLite connection, as a JSON array of rows. -/
def run (db : SQLite) (D : Database) (q : Query) : IO (Except String Lean.Json) := do
  match compile D q with
  | .error e => return .error e
  | .ok sql =>
    let stmt ← db.prepare (toString sql)
    let rows ← collectRows stmt sql.vars q #[]
    return .ok (Lean.Json.arr rows)

end MathQL
