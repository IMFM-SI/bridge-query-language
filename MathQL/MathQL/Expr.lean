import MathQL.Name
import MathQL.Operators
import MathQL.Ty

namespace MathQL

/-- Expressions -/
inductive Expr where
  /-- Integer literal -/
  | int : Int → Expr
  /-- Boolean literal -/
  | bool : Bool → Expr
  /-- String literal -/
  | str : String → Expr
  /-- Predefined constant -/
  | ident : Ident → Expr
  /-- Object ID -/
  | id : DomainName → Expr → Expr
  /-- Field projection -/
  | field : DomainName → Expr → Label → Expr
  /-- Object with the given id -/
  | obj : DomainName → Expr → Expr
  /-- Unary operation -/
  | unop : UnaryOp → Expr → Expr
  /-- Binary operation -/
  | binop : BinaryOp → Expr → Expr → Expr
  /-- Comparison -/
  | compare : ComparisonOp → Ty → Expr → Expr → Expr
  /-- List -/
  | list : List Expr → Expr
  /-- Tuple -/
  | tuple : List Expr → Expr
  /-- Tuple projection -/
  | proj : Expr → Nat → Expr
  /-- Conditional expression -/
  | ite : Expr → Expr → Expr → Expr
  /-- Defined? -/
  | defined : Expr → Expr
  /-- Undefined? -/
  | undefined : Expr → Expr
deriving Repr
