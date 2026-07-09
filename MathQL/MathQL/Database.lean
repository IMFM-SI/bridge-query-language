import MathQL.Name
import MathQL.Ty
import MathQL.Context
import MathQL.SQLExpr
import SQLite

namespace MathQL

structure Column where
  /-- The column in the table -/
  column : String
  /-- The field's type in the query language -/
  ty : Ty
  /-- Does this column participate in the primary key? -/
  isPrimary : Bool
  /-- A human description of the field's meaning -/
  doc : String

structure ForeignKey where
  /-- Which domain the foreign key refers to -/
  domain : DomainName
  /-- Matching columns to the ones in the foreign domain -/
  column : List (String × String)
  /-- A human description of the foreign key -/
  doc : String

structure Schema where
  /-- The table/view in the database this domain refers to -/
  table : String
  /-- Mapping from query language fields to columns in the table -/
  column : List (Label × Column)
  /-- Foreign keys -/
  foreignKey : List (Label × ForeignKey)

def Schema.primaryColumns (sch : Schema) : List String :=
  (sch.column.filter (fun (_, c) => c.isPrimary)).map (fun (_, c) => c.column)

def Schema.getForeignKey (sch : Schema) (l : Label): Result ForeignKey :=
  match sch.foreignKey.lookup l with
  | .some fk => return fk
  | .none => throw s!"uknown foreign key {repr l}"

/-- Mapping from a table schema to Lean -/
structure Realization extends Schema where
  /-- The Lean type of a decoded object -/
  Obj : Type
  /-- Convert the object as a whole to Json-/
  toJson : Obj → Lean.Json
  /-- Render the primary key of a decoded object -/
  idJson : Obj → Lean.Json
  /-- Reads the projected cells into an object -/
  decode : SQLite.RowReader Obj
  /-- Output fields -/
  outputField : List (Label × (Obj → Lean.Json))
  /-- A human description of the domain -/
  doc : String

structure Database where
  /-- A human overview of what the database contains -/
  overview : String
  /-- The constants known to this database -/
  const : List (Ident × Ty × SQL.Expr)
  /-- The domains/tables known to this database, each with its realization -/
  domain : List (DomainName × Realization)
  /-- Example queries, each with a short note -/
  examples : List (String × Lean.Json)

def Database.getDomainContext (D : Database) : DomainContext :=
  D.domain.map fun (n, d) =>
    (n, { inputField := d.column.map fun (l, f) => (l, {ty := f.ty, isPrimary := f.isPrimary})
          domainField := d.foreignKey.map fun (l, fk) => (l, fk.domain)
          outputField := d.outputField.map fun (l, _) => l })

def Database.getContext (D : Database) : Context where
  domain := D.getDomainContext
  ident := D.const.map fun (x, t, _) => (x, .ty t)

/-- A JSON description of the database for the `describe` request: an overview, each
domain with its doc and its queryable fields (label, type, doc) and output fields,
the constants, and example queries. -/
def Database.describe (D : Database) : Lean.Json :=
  let domains := D.domain.map fun (n, dom) =>
    Lean.Json.mkObj
      [ ("name", Lean.Json.str n.name),
        ("doc", Lean.Json.str dom.doc),
        ("inputFields", Lean.Json.arr <| (dom.column.map fun (l, f) =>
          Lean.Json.mkObj
            [ ("label", Lean.Json.str l.name),
              ("type", Lean.Json.str f.ty.render),
              ("doc", Lean.Json.str f.doc) ]).toArray),
        ("domainFields", Lean.Json.arr <| (dom.foreignKey.map fun (l, f) =>
          Lean.Json.mkObj
            [ ("label", Lean.Json.str l.name),
              ("domain", Lean.Json.str f.domain.name),
              ("doc", Lean.Json.str f.doc) ]).toArray),
        ("outputFields", Lean.Json.arr <| (dom.outputField.map fun (l, _) => Lean.Json.str l.name).toArray) ]
  let constants := D.const.map fun (x, t, _) =>
    Lean.Json.mkObj [("name", Lean.Json.str x.name), ("type", Lean.Json.str t.render)]
  let examples := D.examples.map fun (note, q) =>
    Lean.Json.mkObj [("note", Lean.Json.str note), ("query", q)]
  Lean.Json.mkObj
    [ ("overview", Lean.Json.str D.overview),
      ("domains", Lean.Json.arr domains.toArray),
      ("constants", Lean.Json.arr constants.toArray),
      ("examples", Lean.Json.arr examples.toArray) ]

end MathQL
