namespace MathQL

inductive Ident where
  | ident : String → Ident
deriving Repr, BEq, ReflBEq, LawfulBEq

def Ident.name : Ident → String
  | .ident s => s

inductive Label where
  | label : String → Label
deriving Repr, BEq, ReflBEq, LawfulBEq

def Label.name : Label → String
  | .label s => s

inductive DomainName where
  | domain : String → DomainName
deriving Repr, BEq, ReflBEq, LawfulBEq

def DomainName.name : DomainName → String
  | .domain s => s
