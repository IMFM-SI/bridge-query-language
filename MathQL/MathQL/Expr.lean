import MathQL.Name
import MathQL.Operators

namespace MathQL

/-- Expressions -/
inductive Expr where
  | int : Int → Expr
  | bool : Bool → Expr
  | str : String → Expr
  | enum : Ident → Expr
  | var : Ident → Expr
  | field : Expr → Label → Expr
  | unop : UnaryOp → Expr → Expr
  | binop : BinaryOp → Expr → Expr → Expr
  | tuple : List Expr → Expr
  | proj : Expr → Nat → Expr
  | nil : Expr
  | cons : Expr → Expr → Expr
  | someE : Expr → Expr
  | noneE : Expr
  | ite : Expr → Expr → Expr → Expr
deriving Repr
