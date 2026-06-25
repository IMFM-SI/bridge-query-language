/-! The surface abstract syntax: the untyped output of the parser, before
elaboration into a typed term. -/

namespace MathQL.Surface

/-- Surface type expressions, as written in an ascription `(e : τ)`. A bare
    name denotes a domain or an enumeration, resolved against the schema. -/
inductive STy where
  | int
  | bool
  | string
  | option (t : STy)
  | list (t : STy)
  | prod (ts : List STy)
  | name (n : String)
deriving Repr, Inhabited, BEq

/-- Surface patterns. -/
inductive Pat where
  | var (x : String)
  | wild
  | tuple (ps : List Pat)
  | record (fields : List (String × Pat))
  | enumCtor (c : String)
  | someP (p : Pat)
  | noneP
  | nil
  | cons (head tail : Pat)
deriving Repr, Inhabited

/-- Surface expressions. -/
inductive Expr where
  | int (n : Int)
  | bool (b : Bool)
  | str (s : String)
  | var (x : String)
  | field (e : Expr) (label : String)
  | proj (e : Expr) (idx : Nat)
  | record (fields : List (String × Expr))
  | nil
  | cons (head tail : Expr)
  | listLit (items : List Expr)
  | someE (e : Expr)
  | noneE
  | enumCtor (c : String)
  | ite (cond thn els : Expr)
  | mat (scrut : Expr) (alts : List (Pat × Expr))
  | let (pat : Pat) (val body : Expr)
  | unop (op : String) (e : Expr)
  | binop (op : String) (l r : Expr)
  | tuple (items : List Expr)
  | ascribe (e : Expr) (ty : STy)
deriving Repr, Inhabited

/-- A top-level query `{ result | var ∈ domain, condition }`. A query is not an
    expression: it cannot nest or appear as a subterm. -/
structure Query where
  result : Expr
  var : String
  domain : String
  condition : Option Expr
deriving Repr, Inhabited

end MathQL.Surface
