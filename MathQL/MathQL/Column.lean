import SQLite
import Lean.Data.Json

/-! Helpers that read one SQLite column into a semantically-typed Lean value.
Each consumes a single column and advances the row reader's counter, so a
sequence of them decodes a row positionally. -/

namespace MathQL.Column

/-- An INTEGER column as an `Int`. -/
def int : SQLite.RowReader Int := do
  let i ← (SQLite.RowReader.field : SQLite.RowReader Int64)
  return i.toInt

/-- A non-negative INTEGER column as a `Nat`. -/
def nat : SQLite.RowReader Nat := do
  let i ← int
  return i.toNat

/-- A `0`/`1` INTEGER column as a `Bool`. -/
def bool : SQLite.RowReader Bool := SQLite.RowReader.field

/-- A TEXT column as a `String`. -/
def string : SQLite.RowReader String := SQLite.RowReader.field

/-- A nullable non-negative INTEGER column as an `Option Nat`. -/
def natOption : SQLite.RowReader (Option Nat) := do
  let i ← (SQLite.RowReader.field : SQLite.RowReader (Option Int64))
  return i.map fun i => i.toInt.toNat

/-- A TEXT column holding a JSON array of naturals as a `List Nat`. -/
def natList : SQLite.RowReader (List Nat) := do
  let s ← string
  match Lean.Json.parse s >>= fun j => j.getArr? >>= fun a => a.toList.mapM Lean.Json.getNat? with
  | .ok ns => return ns
  | .error e => throw (IO.userError s!"expected a JSON array of naturals: {e}")

end MathQL.Column
