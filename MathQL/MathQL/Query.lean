import MathQL.Context
import MathQL.Expr
import MathQL.Rules

namespace MathQL

structure Query where
  /-- domain variables -/
  vars : List (Ident × DomainName)
  /-- boolean condition -/
  condition : Expr
  /-- output fields, each an alias, the field's type, and the expression -/
  output : List (Ident × Ty × Expr)
  limit : Option Nat
  order : List (Expr × Direction)

end MathQL
