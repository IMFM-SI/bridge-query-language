
inductive Ty (Ground : Type) where
  | unit : Ty Ground
  | ground : Ground → Ty Ground
  | prod : Ty Ground → Ty Ground → Ty Ground

def Ty.interpret {G : Type} (I : G → Type) : Ty G → Type
  | .unit => Unit
  | .ground g => I g
  | .prod t u => t.interpret I × u.interpret I

structure OpSignature (Ground : Type) where
  op : Type
  dom : op → Ty Ground
  cod : op → Ty Ground

structure PredSignature (Ground : Type) where
  pred : Type
  dom : pred → Ty Ground

structure DBSignature (G : Type) where
  attr : Type
  ty : attr → Ty G

inductive Tm (G : Type) (O : OpSignature G) (D : DBSignature G): Ty G → Type where
| tt : Tm G O D Ty.unit
| pair : ∀ {A B : Ty G}, Tm G O D A → Tm G O D B → Tm G O D (.prod A B)
| fst : ∀ {A B : Ty G}, Tm G O D (.prod A B) → Tm G O D A
| snd : ∀ {A B : Ty G}, Tm G O D (.prod A B) → Tm G O D B
| app : ∀ (f : O.op), Tm G O D (O.dom f) → Tm G O D (O.cod f)
| get : ∀ (c : D.attr), Tm G O D (D.ty c)

inductive Query (G : Type) (O : OpSignature G) (P : PredSignature G) (D : DBSignature G) where
| fal : Query G O P D
| tru : Query G O P D
| conj : Query G O P D → Query G O P D → Query G O P D
| pred : ∀ (p : P.pred), Tm G O D (P.dom p) → Query G O P D

structure DB (G : Type) (I : G → Type) (O : OpSignature G) (P : PredSignature G) (D : DBSignature G) where
  Obj : Type
  get : Obj → ∀ (a : D.attr), (D.ty a).interpret I
  exec : Query G O P D → List Obj

namespace Peano
  inductive Ground where
  | nat : Ground

  def Ground.interpret : Ground → Type
  | .nat => Nat

  inductive Op where
  | const : Nat → Op
  | add : Op

  @[reducible]
  def Op.dom : Op → Ty Ground
  | .const _ => .unit
  | .add => .prod (.ground .nat) (.ground .nat)

  @[reducible]
  def Op.cod : Op → Ty Ground
  | .const _ => .ground .nat
  | .add => .ground .nat

  @[reducible]
  def opSignature : OpSignature Ground where
    op := Op
    dom := Op.dom
    cod := Op.cod

  inductive Pred where
  | eq : Pred
  | even : Pred

  @[reducible]
  def Pred.dom : Pred → Ty Ground
  | .eq => .prod (.ground .nat) (.ground .nat)
  | .even => .ground .nat

  @[reducible]
  def predSignature : PredSignature Ground where
    pred := Pred
    dom := Pred.dom

  inductive Attr where
  | size : Attr
  | genus : Attr

  @[reducible]
  def Attr.ty : Attr → Ty Ground
  | .size => .ground .nat
  | .genus => .prod (.ground .nat) (.ground .nat)

  @[reducible]
  def dbSignature : DBSignature Ground where
    attr := Attr
    ty := Attr.ty

end Peano

namespace MyDB
  open Peano

  structure Cow where
    elems : List Nat
    genus : Nat × Nat

  def Cow.size (c : Cow) : Nat := c.elems.length

  def pasture : List Cow := [
    { elems := [1,2,3,4],
      genus := (2, 3)},
    { elems := [1,2,3,4,5,6,7,8,9,20],
      genus := (4, 7)},
    { elems := [1,2,3],
      genus := (2, 5)},
    { elems := [],
      genus := (3, 6)},
    { elems := [1,2,3,4,5],
      genus := (4, 32)},
    { elems := [1,2,3,4],
      genus := (1, 0)},
  ]

  def CowDB : DB Ground Ground.interpret opSignature predSignature dbSignature where
    Obj := Cow
    get := (fun (c : Cow) (a : Attr) => match a with
              | .size => c.size
              | .genus => c.genus
           )
    exec := (fun (q : Query _ _ _ _) => pasture.filter (compile q) )

end MyDB

section Example
  open Peano

  def ten :=
    (.app (Op.const 10) .tt : Tm Ground opSignature dbSignature _)

  def get_size :=
    (.get Attr.size : Tm Ground opSignature dbSignature _)

  def get_genus :=
    (.get Attr.genus : Tm Ground opSignature dbSignature _)

  -- objects of size 10 whose first component of genus is even
  example: Query Ground opSignature predSignature dbSignature :=
    .conj
      (.pred .eq (.pair get_size ten))
      (.pred .even (.fst get_genus))


end Example
