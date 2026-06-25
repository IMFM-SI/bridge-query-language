/-! Abstract syntax of MathQL queries. -/

namespace MathQL

/-- Types of the query language. -/
inductive Ty where
  | int
  | bool
  | string
  | option (t : Ty)
  | list (t : Ty)
  | prod (ts : List Ty)
  | record (domain : String)
deriving Repr, BEq, Inhabited

/-- Expressions: literals, the comprehension variable, projections, operators,
    and tuples. -/
inductive Expr where
  | int (n : Int)
  | bool (b : Bool)
  | str (s : String)
  | var (name : String)
  | field (obj : Expr) (label : String)
  | unop (op : String) (e : Expr)
  | binop (op : String) (l r : Expr)
  | tuple (items : List Expr)
deriving Repr, Inhabited

/-- A comprehension `{ result | var ∈ domain, condition }`. -/
structure Query where
  result : Expr
  var : String
  domain : String
  condition : Option Expr
deriving Repr, Inhabited

end MathQL
