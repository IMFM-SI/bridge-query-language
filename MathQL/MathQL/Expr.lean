import MathQL.Name
import MathQL.Operators
import MathQL.Ty

namespace MathQL

/-- Expressions -/
inductive Expr where
  | int : Int → Expr
  | bool : Bool → Expr
  | str : String → Expr
  | const : Ident → Expr
  | field : Ident → Label → Expr
  | unop : UnaryOp → Expr → Expr
  | binop : BinaryOp → Expr → Expr → Expr
  | compare : ComparisonOp → Ty → Expr → Expr → Expr
  | list : List Expr → Expr
  | tuple : List Expr → Expr
  | proj : Expr → Nat → Expr
  | ite : Expr → Expr → Expr → Expr
  | defined : Expr → Expr
  | undefined : Expr → Expr
deriving Repr
