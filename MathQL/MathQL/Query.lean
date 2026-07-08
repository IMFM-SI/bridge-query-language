import MathQL.Context
import MathQL.Expr
import MathQL.Rules

namespace MathQL

/-- A type-checked output item. -/
inductive OutputItem where
  /-- The whole object, rendered as a JSON object of the domain's output fields -/
  | ident : Ident → OutputItem
  /-- One field of an object -/
  | field : Ident → Label → OutputItem
  /-- The primary key of an object -/
  | id : Ident → OutputItem
deriving BEq

structure Query where
  vars : List (Ident × DomainName)
  condition : Expr
  output : List OutputItem
  limit : Option Nat
  order : List (Expr × Direction)

end MathQL
