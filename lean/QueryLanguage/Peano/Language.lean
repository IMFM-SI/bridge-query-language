import QueryLanguage.Core
import QueryLanguage.DSL

/-! A made up example of a query language that supports natural numbers,
    numeral constants, addition, equality, and the evenness predicate).
-/

namespace Peano.Language

  /-- The only ground type is `.nat` -/
  inductive G where
  | nat : G

  def GM : GroundModel G
  | .nat => Nat

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

  inductive Pred where
  | eq : Pred
  | even : Pred

  def Pred.dom : Pred → Ty G
  | .eq => .prod (.ground .nat) (.ground .nat)
  | .even => .ground .nat

  def P : PredSignature G where
    pred := Pred
    dom := Pred.dom

  def PM : PredModel P GM
  | .eq => (fun (p : Nat × Nat) => p.fst = p.snd)
  | .even => (fun (n : Nat) => n.mod 2 = 0)

  /-! Plugging Peano into the generic DSL. -/

  open DSL

  -- operations: numeral constants and addition
  syntax num                    : query_tm
  syntax query_tm "+" query_tm  : query_tm
  -- predicates
  syntax query_tm "==" query_tm : query_query
  syntax "even" query_tm        : query_query

  macro_rules
    | `(⟦tm| $n:num⟧)                    => `(Tm.call (Op.const $n) Tm.tt)
    | `(⟦tm| $t:query_tm + $u:query_tm⟧) => `(Tm.call Op.add (Tm.pair ⟦tm| $t⟧ ⟦tm| $u⟧))
    | `(⟦q| $t:query_tm == $u:query_tm⟧) => `(Query.pred Pred.eq (Tm.pair ⟦tm| $t⟧ ⟦tm| $u⟧))
    | `(⟦q| even $t:query_tm⟧)           => `(Query.pred Pred.even ⟦tm| $t⟧)

end Peano.Language
