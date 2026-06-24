import QueryLanguage.Peano.Language

/-! The attributes and database signature for the made up Peano query language. -/

namespace Peano.ExampleDBSignature

  open Peano.Language

  inductive Attr where
  | size : Attr
  | genus : Attr

  /-- `size` returns natural numbers and `genus` returns pairs of natural numbers -/
  def Attr.ty : Attr → Ty G
  | .size => .ground .nat
  | .genus => .prod (.ground .nat) (.ground .nat)

  def D : DBSignature G where
    attr := Attr
    ty := Attr.ty

  /-! Surface syntax for the attributes -/

  open DSL

  syntax "get_size"  : query_tm
  syntax "get_genus" : query_tm

  macro_rules
    | `(⟦tm| get_size⟧)  => `(Tm.getAttr Attr.size)
    | `(⟦tm| get_genus⟧) => `(Tm.getAttr Attr.genus)

  /-! Examples -/

  -- structural terms (`Ty.unit` is fixed by the ascription)
  #reduce (⟦tm| () ⟧                : Tm O D .unit)
  #reduce (⟦tm| (() , ()) ⟧         : Tm O D (.prod .unit .unit))
  #reduce (⟦tm| fst (() , ()) ⟧     : Tm O D .unit)

  -- operations and attributes
  #reduce (⟦tm| 42 ⟧                : Tm O D (.ground .nat))
  #reduce (⟦tm| 24 + 42 ⟧           : Tm O D (.ground .nat))
  #reduce (⟦tm| get_size ⟧          : Tm O D (.ground .nat))
  #reduce (⟦tm| get_genus ⟧         : Tm O D (.prod (.ground .nat) (.ground .nat)))

  -- queries
  #reduce (⟦q| false ⟧              : Query O P D)
  #reduce (⟦q| true && false ⟧      : Query O P D)
  #reduce (⟦q| 2 == 2 ⟧             : Query O P D)
  #reduce (⟦q| even 2 ⟧             : Query O P D)

end Peano.ExampleDBSignature
