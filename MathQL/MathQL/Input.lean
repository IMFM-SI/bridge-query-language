import MathQL.Operators

/-! The surface abstract syntax: the untyped output of the parser, before
elaboration into a typed term. -/

namespace MathQL.Input

/-- Surface type expressions, as written in an ascription `(e : τ)`. A bare
    name denotes a domain or an enumeration, resolved against the schema. -/
inductive Ty where
  | int
  | bool
  | string
  | option (t : Ty)
  | list (t : Ty)
  | prod (ts : List Ty)
  | name (n : String)
deriving Repr, BEq

/-- Surface patterns. -/
inductive Pattern where
  | var (x : String)
  | wild
  | tuple (ps : List Pattern)
  | record (fields : List (String × Pattern))
  | enumCtor (c : String)
  | someP (p : Pattern)
  | noneP
  | nil
  | cons (head tail : Pattern)
deriving Repr

/-- Surface expressions. -/
inductive Expr where
  | int (n : Int)
  | bool (b : Bool)
  | str (s : String)
  | var (x : String)
  | field (e : Expr) (label : String)
  | proj (e : Expr) (idx : Nat)
  | nil
  | cons (head tail : Expr)
  | listLit (items : List Expr)
  | someE (e : Expr)
  | noneE
  | enumCtor (c : String)
  | ite (cond thn els : Expr)
  | cases (scrut : Expr) (alts : List (Pattern × Expr))
  | bind (pat : Pattern) (val body : Expr) -- let-binding
  | tuple (items : List Expr)
  | ascribe (e : Expr) (ty : Ty)
  | unop (op : UnaryOp) (e : Expr)
  | binop (op : BinaryOp) (l r : Expr)
deriving Repr

/-- A top-level query `{ result | var ∈ domain, condition }`. A query is not an
    expression: it cannot nest or appear as a subterm. -/
structure Query where
  result : Expr
  var : String
  domain : String
  condition : Option Expr
deriving Repr

end MathQL.Input
