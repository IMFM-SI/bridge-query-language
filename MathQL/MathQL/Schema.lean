import SQLite
import MathQL.Syntax
import MathQL.Value

/-! Schema descriptors: how a domain's invariants map onto SQLite columns. -/

namespace MathQL

/-- How a stored cell is decoded into a `Value`. -/
inductive ColumnKind where
  | int
  | bool
  | string
  | jsonIntList
  | optionInt
deriving Repr, BEq, Inhabited

/-- One invariant: its query type, the column holding it, and how to decode it. -/
structure Attribute where
  name : String
  column : String
  ty : Ty
  kind : ColumnKind
deriving Repr, Inhabited

/-- A collection of objects backed by one table. -/
structure Domain where
  name : String
  table : String
  attributes : List Attribute
deriving Repr, Inhabited

/-- A SQLite file together with the domains it provides. -/
structure Database where
  path : System.FilePath
  domains : List Domain
deriving Inhabited

/-- A value bound to a SQL `?` placeholder. -/
inductive Param where
  | int (n : Int)
  | str (s : String)
deriving Repr, Inhabited

def Domain.find? (d : Domain) (name : String) : Option Attribute :=
  d.attributes.find? (·.name == name)

def Database.domain? (db : Database) (name : String) : Option Domain :=
  db.domains.find? (·.name == name)

private def parseIntList (s : String) : Value :=
  let cleaned := String.ofList (s.toList.filter fun c => c != '[' && c != ']' && c != ' ')
  let parts := (cleaned.splitOn ",").filter (· != "")
  Value.list (parts.filterMap fun p => p.toInt?.map Value.int)

/-- Decode column `col` (0-indexed) of the current row according to `kind`. -/
def decodeColumn (kind : ColumnKind) (stmt : SQLite.Stmt) (col : Int32) : IO Value := do
  if ← stmt.columnNull col then
    return Value.null
  else match kind with
    | .int | .optionInt => return Value.int (← stmt.columnInt64 col).toInt
    | .bool => return Value.bool ((← stmt.columnInt64 col) != 0)
    | .string => return Value.str (← stmt.columnText col)
    | .jsonIntList => return parseIntList (← stmt.columnText col)

/-- Bind `param` to placeholder `idx` (1-indexed) of `stmt`. -/
def bindParam (stmt : SQLite.Stmt) (idx : Int32) : Param → IO Unit
  | .int n => stmt.bindInt64 idx (Int64.ofInt n)
  | .str s => stmt.bindText idx s

end MathQL
