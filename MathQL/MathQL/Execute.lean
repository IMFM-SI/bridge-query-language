import MathQL.Compile
import MathQL.Database
import SQLite
import Lean.Data.Json

/-! Execution of a type-checked query against a SQLite connection, producing a
JSON array of result rows. -/

namespace MathQL

/-- Read one row's output values, keyed by `(variable, label)`. Each bound variable's
object is decoded in turn (the column counter threads across the join), then its output
fields are applied. -/
def rowFields (binds : List (Ident × Domain)) :
    SQLite.RowReader (List ((Ident × Label) × Lean.Json)) :=
  binds.foldlM
    (fun acc (x, dom) => do
      let o ← dom.decode
      return acc ++ dom.outputField.map fun (l, f) => ((x, l), f o))
    []

/-- Assemble a row's JSON object in the query's output order. -/
def rowObject (q : Query) (fields : List ((Ident × Label) × Lean.Json)) : Lean.Json :=
  Lean.Json.mkObj <| q.output.map fun (x, l) =>
    (s!"{x.name}.{l.name}", (fields.lookup (x, l)).getD Lean.Json.null)

/-- Step through every result row, decoding each into its output object. -/
partial def collectRows (stmt : SQLite.Stmt) (binds : List (Ident × Domain)) (q : Query)
    (acc : Array Lean.Json) : IO (Array Lean.Json) := do
  if ← stmt.step then
    let fields ← (rowFields binds).run stmt
    collectRows stmt binds q (acc.push (rowObject q fields))
  else
    return acc

/-- Run a type-checked query against an open SQLite connection, as a JSON array of rows. -/
def run (db : SQLite) (D : Database) (q : Query) : IO (Except String Lean.Json) := do
  match compile D q with
  | .error e => return .error e
  | .ok sql =>
    let stmt ← db.prepare (toString sql)
    let binds := q.vars.filterMap fun (x, n) => (D.domain.lookup n).map fun dom => (x, dom)
    let rows ← collectRows stmt binds q #[]
    return .ok (Lean.Json.arr rows)

end MathQL
