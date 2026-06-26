import MathQL.Operators

namespace MathQL.SQL

/-- SQL scalar/boolean expressions. -/
inductive Expr where
  | col       : (table column : String) → Expr
  | int       : Int → Expr
  | str       : String → Expr
  | bool      : Bool → Expr
  | null      : Expr
  | unop      : UnaryOp → Expr → Expr
  | binop     : BinaryOp → Expr → Expr → Expr
  | isNull    : Expr → Expr
  | isNotNull : Expr → Expr
deriving Repr

/-- A SQL `SELECT` query. -/
structure Query where
  select : List Expr
  tables : List (String × String)   -- (table, alias)
  cond   : Expr
deriving Repr

end MathQL.SQL
