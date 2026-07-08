import MathQL.Context
import MathQL.Expr
import MathQL.Rules

namespace MathQL

structure Query where
  /-- domain variables -/
  vars : List (Ident × DomainName)
  /-- boolean condition -/
  condition : Expr
  /-- output fields with mandatory aliases -/
  output : List (Ident × Expr)
  limit : Option Nat
  order : List (Expr × Direction)

end MathQL
