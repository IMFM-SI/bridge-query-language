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
  | list : List Expr → Expr
  | ite : Expr → Expr → Expr → Expr
  | tuple : List Expr → Expr
  | unop : UnaryOp → Expr → Expr
  | binop : BinaryOp → Expr → Expr → Expr
  | compare : ComparisonOp → Expr → Expr → Expr
  | defined : Expr → Expr
  | undefined : Expr → Expr
deriving Repr

/-- An output item: a domain variable `x` (the whole object), or a field
    projection `x.field`. -/
structure OutputItem where
  var : String
  field : Option String
deriving Repr

/-- A domain binding `x ∈ D`: the variable and the domain it ranges over. -/
structure Binding where
  var : String
  domain : String
deriving Repr

/-- An `ORDER BY` entry: an expression and a sort direction. -/
structure OrderEntry where
  expr : Expr
  dir : Direction
deriving Repr

/-- A query. `condition`, `order`, and `limit` are optional in the input; the
    type-checker fills in `true`, the empty list, and none respectively. -/
structure Query where
  domains : List Binding
  output : List OutputItem
  condition : Option Expr := none
  order : Option (List OrderEntry) := none
  limit : Option Nat := none
deriving Repr

end MathQL.Input
