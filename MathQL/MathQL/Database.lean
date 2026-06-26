import MathQL.Name
import MathQL.Ty

namespace MathQL

structure InputField where
  /-- The field name in the query language -/
  label : Label
  /-- The column in the table -/
  column : String
  /-- The type of the field in the query langauge -/
  ty : Ty

structure Domain where
  /-- The table/view in the database this domain refers to -/
  table : String
  /-- Fields of the type, equivalently the columns of the table -/
  inputField : List (Label × InputField)
  /-- The output fields -/
  Obj : Type
  /-- Output fields -/
  outputField : List (Label × Σ (t : Type), Obj → t)

structure Database where
  /-- The constants known to this database -/
  const : List (Ident × Ty × String) -- TODO: shouldn't be a string, but something like SQLExpression
  /-- The domains/tables known to this database -/
  domain : List (DomainName × Domain)

end MathQL
