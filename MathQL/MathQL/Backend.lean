import MathQL.Database
import MathQL.QueryJson
import MathQL.Typing
import MathQL.Postprocess
import MathQL.SQLite.Execute
import MathQL.SQLite.SchemaInfo
import Lean.Data.Json

/-! The selected backend and the request runner shared by every backend. A `Session` holds the
dataset, the signatures of the selected backend's registrations, and that backend's executor.
Checking, postprocessing and the response are the same whichever backend runs the SQL. -/

namespace MathQL

/-- An open connection to one dataset on one backend. -/
structure Session where
  /-- The shared description of the dataset -/
  database : Database
  /-- The selected backend's constant and SQL function signatures -/
  signatures : Signatures
  /-- Compile and run a checked query, giving the ordered rows, each its output columns in order -/
  execute : Query → IO (Except String (Array (List (Ident × Lean.Json))))

/-- A session over an open SQLite connection, with the registrations `R`. -/
def Session.ofSQLite (db : _root_.SQLite) (D : Database) (R : SQLite.Registrations) :
    IO Session := do
  let isSafeAlias ← SQLite.safeAliasPredicate db D
  return { database := D, signatures := R.signatures, execute := SQLite.execute db D R isSafeAlias }

/-- A session over the SQLite file at `path`, opened read-only. -/
def Session.openSQLite (path : System.FilePath) (D : Database) (R : SQLite.Registrations) :
    IO Session := do
  Session.ofSQLite (← _root_.SQLite.openWith path .readonly) D R

/-- Run a checked query and postprocess each row, as a JSON array of rows, each an array of
`[name, value]` pairs: the output columns, then the postprocess entries. -/
def Session.run (s : Session) (q : Query) : IO (Except String Lean.Json) := do
  match ← s.execute q with
  | .error e => return .error e
  | .ok rows =>
    let funs := s.database.postFunction.map fun ⟨f, _, c⟩ => (f, c)
    let full := rows.map fun row =>
      row ++ evalPostprocess { ident := row, function := funs } q.postprocess
    return .ok (Lean.Json.arr (full.map fieldsToJson))
where
  fieldsToJson (lst : List (Ident × Lean.Json)) : Lean.Json :=
    .arr (lst.map (fun (x, j) => .arr #[.str x.name, j])).toArray

/-- Answer one request `Json` with its response `Json`. -/
def Session.handle (s : Session) (j : Lean.Json) : IO Lean.Json := do
  match j.getObjVal? "describe" with
  | .ok _ => return s.database.describe s.signatures.const
  | .error _ =>
    match Input.Query.fromJson j >>= checkQuery s.database s.signatures with
    | .error e => return Lean.Json.mkObj [("error", Lean.Json.str e)]
    | .ok q =>
      match ← s.run q with
      | .error e => return Lean.Json.mkObj [("error", Lean.Json.str e)]
      | .ok rows => return Lean.Json.mkObj [("rows", rows)]

end MathQL
