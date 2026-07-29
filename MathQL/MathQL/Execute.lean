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
def rowObject (cs : List (Ident × Ty × Expr)) : SQLite.RowReader (List (Ident × Lean.Json)) := do
  cs.mapM fun (x, t, _) => do
    let v ← decodeCell t
    return (x, v)

def evalPostExpr (env : List (Ident × Lean.Json)) : PostExpr → Lean.Json
| .int n => .num n
| .ident x =>
  match env.lookup x with
  | none => .null
  | some v => v

def evalPostprocess (env : List (Ident × Lean.Json)) :
  List (Ident × Ty × PostExpr) → List (Ident × Lean.Json)
| [] => []
| (x, _, e) :: ps =>
  let v := evalPostExpr env e
  let vs := evalPostprocess ((x, v) :: env) ps
  (x, v) :: vs

/-- Step through every result row, decoding each into its output object. -/
partial def collectRows (stmt : SQLite.Stmt) (q : Query) (acc : Array (List (Ident × Lean.Json))) :
    IO (Array (List (Ident × Lean.Json))) := do
  if ← stmt.step then
    let row ← (rowObject q.output).run stmt
    let post := evalPostprocess row q.postprocess
    collectRows stmt q (acc.push (row ++ post))
  else
    return acc

/-- Run a type-checked query against an open SQLite connection, as a JSON array of rows. -/
def run (db : SQLite) (D : Database) (q : Query) : IO (Except String Lean.Json) := do
  match compileQuery D q with
  | .error e => return .error e
  | .ok sql =>
    let stmt ← db.prepare (toString sql)
    let rows ← collectRows stmt q #[]
    return .ok (Lean.Json.arr (rows.map fieldsToJson))
where
  fieldsToJson (lst : List (Ident × Lean.Json)) : Lean.Json :=
    .arr (lst.map (fun (x, j) => .arr #[.str x.name, j])).toArray

end MathQL
