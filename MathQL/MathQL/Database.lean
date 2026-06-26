import MathQL.Name
import MathQL.Ty
import MathQL.Context
import MathQL.SQL
import SQLite

namespace MathQL

structure InputField where
  /-- The field name in the query language -/
  label : Label
  /-- The column in the table -/
  column : String
  /-- The type of the field in the query langauge -/
  ty : Ty

structure Schema where
  /-- The table/view in the database this domain refers to -/
  table : String
  /-- Fields of the type, equivalently the columns of the table -/
  inputField : List (Label × InputField)
  /-- The columns this domain projects, in order -/
  select : List String

structure Domain extends Schema where
  /-- The Lean type of a decoded object -/
  Obj : Type
  /-- Reads the projected cells into an object -/
  decode : SQLite.RowReader Obj
  /-- Output fields -/
  outputField : List (Label × (Obj → Lean.Json))

structure Database where
  /-- The constants known to this database -/
  const : List (Ident × Ty × SQL.Expr)
  /-- The domains/tables known to this database -/
  domain : List (DomainName × Domain)

def Database.getDomainContext (D : Database) : DomainContext :=
  D.domain.map fun (n, d) =>
    (n, { inputField := d.inputField.map fun (l, f) => (l, f.ty)
          outputField := d.outputField.map fun (l, _) => l })

def Database.getContext (D : Database) : Context where
  domain := D.getDomainContext
  var := D.const.map fun (x, t, _) => (x, .const t)

end MathQL
