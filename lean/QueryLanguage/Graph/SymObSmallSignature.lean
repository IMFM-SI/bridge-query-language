import QueryLanguage.Graph.Language

/-! The attributes and database signature for the graph query language.

    A graph has two queryable attributes, mirroring the columns of the `graph`
    table in the SQLite database: its `order` (number of vertices) and its
    `size` (number of edges), both natural numbers. -/

namespace Graph

  inductive Attr where
  | order : Attr
  | size  : Attr

  /-- Both attributes are natural numbers. -/
  def Attr.ty : Attr → Ty G
  | .order => .ground .nat
  | .size  => .ground .nat

  def D : DBSignature G where
    attr := Attr
    ty := Attr.ty

  /-! Surface syntax for the attributes -/

  open DSL

  syntax "get_order" : query_tm
  syntax "get_size"  : query_tm

  macro_rules
    | `(⟦tm| get_order⟧) => `(Tm.getAttr Attr.order)
    | `(⟦tm| get_size⟧)  => `(Tm.getAttr Attr.size)

  /-! Example terms and queries -/

  -- terms: attributes, constants, addition
  #reduce (⟦tm| get_order ⟧                : Tm O D (.ground .nat))
  #reduce (⟦tm| get_size ⟧                 : Tm O D (.ground .nat))
  #reduce (⟦tm| get_order + get_size ⟧     : Tm O D (.ground .nat))

  -- queries: comparisons against order and size
  #reduce (⟦q| get_order == 5 ⟧            : Query O P D)
  #reduce (⟦q| get_size <= 10 ⟧            : Query O P D)
  #reduce (⟦q| (get_order == 4) && (get_size < 6) ⟧ : Query O P D)

end Graph
