import MathQL.Context
import MathQL.Expr
import MathQL.Rules

namespace MathQL

structure Query where
  vars : List (Ident × DomainName)
  condition : Expr
  output : List (Ident × Label)

end MathQL
