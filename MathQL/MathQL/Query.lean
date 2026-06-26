import MathQL.Context
import MathQL.Expr
import MathQL.Rules

namespace MathQL

structure Query where
  context : Context
  condition : Expr
  conditionBool : ExprOfTy context condition .bool
  output : List (Ident × Label)

end MathQL
