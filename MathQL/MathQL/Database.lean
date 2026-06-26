import MathQL.Name
import MathQL.Ty
import MathQL.Context
import MathQL.SQLExpr
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
  /-- Convert the object as a whole to Json-/
  toJson : Obj → Lean.Json
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

/-- A JSON description of the database for the `describe` request: each domain with
its queryable fields (label and type) and its output fields, plus the constants. -/
def Database.schema (D : Database) : Lean.Json :=
  let domains := D.domain.map fun (n, dom) =>
    Lean.Json.mkObj
      [ ("name", Lean.Json.str n.name),
        ("fields", Lean.Json.arr <| (dom.inputField.map fun (l, f) =>
          Lean.Json.mkObj [("label", Lean.Json.str l.name), ("type", Lean.Json.str f.ty.render)]).toArray),
        ("output", Lean.Json.arr <| (dom.outputField.map fun (l, _) => Lean.Json.str l.name).toArray) ]
  let constants := D.const.map fun (x, t, _) =>
    Lean.Json.mkObj [("name", Lean.Json.str x.name), ("type", Lean.Json.str t.render)]
  Lean.Json.mkObj
    [ ("domains", Lean.Json.arr domains.toArray),
      ("constants", Lean.Json.arr constants.toArray) ]

end MathQL
