import MathQL.Ty

namespace MathQL

inductive Pattern where
  | wild : Pattern
  | var : Ident → Pattern
  | tuple : List Pattern → Pattern
  -- claude: anything else?
deriving Repr
