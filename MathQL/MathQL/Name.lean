namespace MathQL

inductive Ident where
  | ident : String → Ident
deriving Repr, BEq, ReflBEq, LawfulBEq

def Ident.name : Ident → String
  | .ident s => s

instance : ToString Ident := ⟨Ident.name⟩

inductive Label where
  | label : String → Label
deriving Repr, BEq, ReflBEq, LawfulBEq

def Label.name : Label → String
  | .label s => s

instance : ToString Label := ⟨Label.name⟩

inductive DomainName where
  | domain : String → DomainName
deriving Repr, BEq, ReflBEq, LawfulBEq

def DomainName.name : DomainName → String
  | .domain s => s

instance : ToString DomainName := ⟨DomainName.name⟩
