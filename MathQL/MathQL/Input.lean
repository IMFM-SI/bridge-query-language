import MathQL.Operators

/-! The input abstract syntax: the untyped output of the parser, before
elaboration into a typed term. -/

namespace MathQL.Input

/-- Input expressions. -/
inductive Expr where
  | int : Int → Expr
  | bool : Bool → Expr
  | str : String → Expr
  | const : String → Expr
  | field : String → String → Expr
  | proj : Expr → Nat → Expr
  | nil : Expr
  | cons : Expr → Expr → Expr
  | listLit : List Expr → Expr
  | ite : Expr → Expr → Expr → Expr
  | tuple : List Expr → Expr
  | unop : UnaryOp → Expr → Expr
  | binop : BinaryOp → Expr → Expr → Expr
  | defined : Expr → Expr
  | undefined : Expr → Expr
deriving Repr

/-- A top-level query `{ output | var ∈ domain, condition }`. A query is not an
    expression: it cannot nest or appear as a subterm. -/
structure Query where
  output : List (String × String)
  vars : List (String × String)
  condition : Expr
deriving Repr

end MathQL.Input
