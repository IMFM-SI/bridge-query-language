import MathQL.Name
import MathQL.Ty

namespace MathQL

structure Field where
  /-- The field name in the query language -/
  label : Label
  /-- The column in the table -/
  column : String
  /-- The type of the field in the query langauge -/
  ty: Ty

structure Domain where
  /-- The named type that this domain denotes -/
  name : Ident
  /-- The table/view in the database this domain refers to -/
  table : String
  /-- Fields of the type, equivalently the columns of the table -/
  fields : List Field

structure Enum where
  /-- The name of the type that this enum denotes -/
  name : Ident
  /-- The mapping from constructors to SQL values -/
  constructors : List (Ident × String)

structure Database where
  domains : List Domain
  enums : List Enum


end MathQL
