import QueryLanguage.Core
import QueryLanguage.DSL

/-! A query language instance for querying graphs by their *order* (number of
    vertices) and *size* (number of edges).

    The only ground type is `.nat`, since orders and sizes are non-negative
    integers. We support numeral constants, addition, and the usual numeric
    comparisons `=`, `≤`, `<`, `≥`, `>`. The attributes are `order` and `size`. -/

namespace Graph.Language

  /-- The only ground type is `.nat`. -/
  inductive G where
  | nat : G

  def GM : GroundModel G
  | .nat => Nat

  /-- Operations: numeral constants and addition. -/
  inductive Op where
  | const : Nat → Op
  | add : Op

  def Op.dom : Op → Ty G
  | .const _ => .unit
  | .add => .prod (.ground .nat) (.ground .nat)

  def Op.cod : Op → Ty G
  | .const _ => .ground .nat
  | .add => .ground .nat

  def O : OpSignature G where
    op := Op
    dom := Op.dom
    cod := Op.cod

  def OM : OpModel O GM
  | .const n => (fun _ => n)
  | .add => fun (p : Nat × Nat) => p.fst + p.snd

  /-- Predicates: the standard numeric comparisons. -/
  inductive Pred where
  | eq : Pred
  | le : Pred
  | lt : Pred
  | ge : Pred
  | gt : Pred

  /-- Every comparison relates two natural numbers. -/
  def Pred.dom : Pred → Ty G
  | .eq | .le | .lt | .ge | .gt => .prod (.ground .nat) (.ground .nat)

  def P : PredSignature G where
    pred := Pred
    dom := Pred.dom

  def PM : PredModel P GM
  | .eq => (fun (p : Nat × Nat) => p.fst == p.snd)
  | .le => (fun (p : Nat × Nat) => p.fst ≤ p.snd)
  | .lt => (fun (p : Nat × Nat) => p.fst < p.snd)
  | .ge => (fun (p : Nat × Nat) => p.fst ≥ p.snd)
  | .gt => (fun (p : Nat × Nat) => p.fst > p.snd)

  /-! Plugging Graph into the generic DSL. -/

  open DSL

  -- operations: numeral constants and addition
  syntax num                    : query_tm
  syntax query_tm "+" query_tm  : query_tm
  -- predicates: the comparisons
  syntax query_tm "==" query_tm : query_query
  syntax query_tm "<=" query_tm : query_query
  syntax query_tm "<"  query_tm : query_query
  syntax query_tm ">=" query_tm : query_query
  syntax query_tm ">"  query_tm : query_query

  macro_rules
    | `(⟦tm| $n:num⟧)                    => `(Tm.call (Op.const $n) Tm.tt)
    | `(⟦tm| $t:query_tm + $u:query_tm⟧) => `(Tm.call Op.add (Tm.pair ⟦tm| $t⟧ ⟦tm| $u⟧))
    | `(⟦q| $t:query_tm == $u:query_tm⟧) => `(Query.pred Pred.eq (Tm.pair ⟦tm| $t⟧ ⟦tm| $u⟧))
    | `(⟦q| $t:query_tm <= $u:query_tm⟧) => `(Query.pred Pred.le (Tm.pair ⟦tm| $t⟧ ⟦tm| $u⟧))
    | `(⟦q| $t:query_tm < $u:query_tm⟧)  => `(Query.pred Pred.lt (Tm.pair ⟦tm| $t⟧ ⟦tm| $u⟧))
    | `(⟦q| $t:query_tm >= $u:query_tm⟧) => `(Query.pred Pred.ge (Tm.pair ⟦tm| $t⟧ ⟦tm| $u⟧))
    | `(⟦q| $t:query_tm > $u:query_tm⟧)  => `(Query.pred Pred.gt (Tm.pair ⟦tm| $t⟧ ⟦tm| $u⟧))

end Graph.Language
