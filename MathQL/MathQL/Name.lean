namespace MathQL

inductive Ident where
  | ident : String → Ident
deriving Repr, BEq, ReflBEq, LawfulBEq

inductive Label where
  | label : String → Label
deriving Repr, BEq, ReflBEq, LawfulBEq
