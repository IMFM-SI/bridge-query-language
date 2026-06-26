import MathQL.Context
import MathQL.Expr
import MathQL.Rules

namespace MathQL

structure Query where
  vars : List (Ident × DomainName)
  condition : Expr
  output : List (Ident × Option Label)
  limit : Option Nat
  order : List (Expr × Direction)

end MathQL
