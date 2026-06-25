/-!
  This is a core setup for a query language thats acts as an interface
  between Lean and a database. There is no presumption here about how the
  database is implemented, we only assume that it knows how to execute
  queries.

  The end user would not use these types directly. There will be another
  layer that translates user queries.

  Everything below is a scaffolding that needs to be fleshed out.
  (For example, there is only conjunction, but it should be easy to add more logic.)
-/


/-- The types of terms appearing in a query. It is parameterized by
    a type of ground types that the database knows about. At present
    we only support n-tuples, coded as nested pairs, as they are needed to
    implement n-ary primitive functions and primitive predicates.

    Think of the elements of `Ty Ground` as *codes* of types.
-/
inductive Ty (Ground : Type) where
  | unit : Ty Ground
  | ground : Ground → Ty Ground
  | prod : Ty Ground → Ty Ground → Ty Ground

/-- Interpretation of ground types as Lean types. -/
class GroundModel (Ground : Type) where
  ground_interpret : Ground → Type

/-- Given an interpretation of ground types, we can interpret
    any type (code) as a Lean type. -/
def Ty.interpret (G : Type) [GM : GroundModel G] : Ty G → Type
  | .unit => Unit
  | .ground g => GM.ground_interpret g
  | .prod t u => t.interpret G × u.interpret G

/-- An operation signature specifies which primitive operations
    can appear in the terms in queries. Typical examples might be
    arithmetical operations. -/
class OpSignature (Ground : Type) (Op : Type) where
  /-- the domain of an operation symbol -/
  dom : Op → Ty Ground
  /-- the codomain of an operation symbol -/
  cod : Op → Ty Ground

/-- Interpretation of operations as Lean functions. -/
class OpModel G Op [O : OpSignature G Op] [GM : GroundModel G] where
  op_interpret : ∀ (f : Op), (O.dom f).interpret → (O.cod f).interpret

/-- A predicate signature specifies which primitive predicates
    (relations) can appear in queries. Typical examples might
    be arithmetical comparison `<` and equality `=`.
    Note that each type may be equipped with its own notion of
    equality, but need not to. -/
class PredSignature (Ground : Type) (Pred : Type) where
  /-- the domain of a predicate symbol -/
  dom : Pred → Ty Ground

/-- Interpretation of predicates as Lean predicates. -/
class PredModel G Pred [P : PredSignature G Pred] [GM : GroundModel G] where
  pred_interpret : ∀ (p : Pred), (P.dom p).interpret → Bool

/-- The capabilities of a database are described by a signature.
    At present we just assume that each entry (mathematical object)
    in the database has some attributes (e.g. columns or views).

    Queries to the database can refer to the attributes as if they
    were 0-ary operations. -/
class DBSignature (G : Type) Attr where
  /-- the type of an attribute -/
  ty : Attr → Ty G

/-- Interpretation of attribute selectors for database objects. -/
class DBModel G (Attr : Type) [D : DBSignature G Attr] [GM : GroundModel G] (Obj : Type) where
  get : Obj → ∀ (a : Attr), (D.ty a).interpret

/-- The terms that may appear in a query. -/
inductive Tm G Op (Attr : Type) [O : OpSignature G Op] [D : DBSignature G Attr] : Ty G → Type where
| tt : Tm G Op Attr Ty.unit
| pair : ∀ {A B : Ty G}, Tm G Op Attr A → Tm G Op Attr B → Tm G Op Attr (.prod A B)
| fst : ∀ {A B : Ty G}, Tm G Op Attr (.prod A B) → Tm G Op Attr A
| snd : ∀ {A B : Ty G}, Tm G Op Attr (.prod A B) → Tm G Op Attr B
| app : ∀ (f : Op), Tm G Op Attr (O.dom f) → Tm G Op Attr (O.cod f)
| get : ∀ (c : Attr), Tm G Op Attr (D.ty c)

/-- Interpretation of terms as lean values -/
def Tm.interpret {G : Type} {Op : Type} {Attr : Type} {Obj}
                 [O : OpSignature G Op] [D : DBSignature G Attr]
                 {GM : GroundModel G}
                 [OM : OpModel G Op]
                 [DM : DBModel G Attr Obj]
                 (obj : Obj)
                 {ty : Ty G} :
                 Tm G Op Attr ty → Ty.interpret G ty
| .tt => .unit
| .pair s t => (s.interpret obj, t.interpret obj)
| .fst t => Prod.fst (t.interpret obj)
| .snd t => Prod.snd (t.interpret obj)
| .app f t => OM.op_interpret f (t.interpret obj)
| .get a => DM.get obj a

/-- A query is a logical formula. -/
inductive Query (G : Type) (Op : Type) (Pred : Type) (Attr : Type)
                [O : OpSignature G Op] [P : PredSignature G Pred] [D : DBSignature G Attr] where
| false : Query G Op Pred Attr
| true : Query G Op Pred Attr
| conj : Query G Op Pred Attr → Query G Op Pred Attr → Query G Op Pred Attr
| pred : ∀ (p : Pred), Tm G Op Attr (P.dom p) → Query G Op Pred Attr

/-- Interpretation of queries as boolean truth values in Lean. -/
def Query.interpret G Op Pred Attr Obj
                    [O : OpSignature G Op] [P : PredSignature G Pred] [D : DBSignature G Attr]
                    [GM : GroundModel G] [OM : OpModel G Op] [PM : PredModel G Pred] [DM : DBModel G Attr Obj]
                    (obj : Obj) : Query G Op Pred Attr → Bool
| .false => Bool.false
| .true => Bool.true
| .conj p q => p.interpret G Op Pred Attr Obj obj && q.interpret G Op Pred Attr Obj obj
| .pred p t => PM.pred_interpret p (t.interpret obj)

/-- A database stores objects of a given type `Obj`. It specifies how
    the attributes are interpreted, and it can execute queries that fetch
    lists of objects. In the future we will likely replace lists with
    a more suitable datastructure, such as a stream or an iterator. -/
class DB G Op Pred Attr Model
         [O : OpSignature G Op] [P : PredSignature G Pred] [D : DBSignature G Attr]
         [GM : GroundModel G] [OM : OpModel G Op] [PM : PredModel G Pred]
         [M : DBModel G Attr Model]
 where
  /-- Execute a query and return the list of objects satisfying it -/
  exec : Query G Op Pred Attr → List Model
  /-- Correctness of queries states: all objects that a query returns satisfy the query -/
  correct : ∀ (q : Query G Op Pred Attr), (exec q).all (q.interpret G Op Pred Attr Model)

namespace Peano
  /-! An example of a query language that supports natural numbers,
    numeral constants, addition, equality =, the "even" predicate,
    and the attributes `size` and `genus` (this is made up). -/

  /-- The only ground type is `.nat` -/
  inductive G where
  | nat : G

  def G.interpret : G → Type
  | .nat => Nat

  instance : GroundModel G where
    ground_interpret := G.interpret

  /-- There are natural number constants and a binary addition operation. -/
  inductive Op where
  | const : Nat → Op
  | add : Op

  def Op.dom : Op → Ty G
  | .const _ => .unit
  | .add => .prod (.ground .nat) (.ground .nat)

  def Op.cod : Op → Ty G
  | .const _ => .ground .nat
  | .add => .ground .nat

  instance : OpSignature G Op where
    dom := Op.dom
    cod := Op.cod

  def Op.interpret : ∀ (f : Op), (Op.dom f).interpret → (Op.cod f).interpret
  | .const n => (fun _ => n)
  | .add => fun (p : Nat × Nat) => p.fst + p.snd

  instance : OpModel G Op where
    op_interpret := Op.interpret

  /-- There are two predicate symbols, equality and evenness. -/
  inductive Pred where
  | eq : Pred
  | even : Pred

  def Pred.dom : Pred → Ty G
  | .eq => .prod (.ground .nat) (.ground .nat)
  | .even => .ground .nat

  instance : PredSignature G Pred where
    dom := Pred.dom

  def Pred.interpret : ∀ (p : Pred), (Pred.dom p).interpret → Bool
  | .eq => (fun (p : Nat × Nat) => p.fst = p.snd)
  | .even => (fun (n : Nat) => n.mod 2 = 0)

  instance : PredModel G Pred where
    pred_interpret := Pred.interpret

  /-- Every entry in the database has two attributes. -/
  inductive Attr where
  | size : Attr
  | genus : Attr

  /-- `size` returns natural numbers and `genus` returns pairs of natural numbers -/
  def Attr.ty : Attr → Ty G
  | .size => .ground .nat
  | .genus => .prod (.ground .nat) (.ground .nat)

  instance : DBSignature G Attr where
    ty := Attr.ty

end Peano

namespace MyDB
  /-! A small database, implemented simply as a list of
      objects. -/

  open Peano

  /-- The database stores a bunch of cows, where each cow
      is given by a list of numbers and a genus. -/
  structure Obj where
    elems : List Nat
    genus : Nat × Nat
  deriving Repr

  /-- The size of a cow is the length of its list. -/
  def Obj.size (c : Obj) : Nat := c.elems.length

  /-- The information stored in the database. -/
  def pasture : List Obj := [
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

  /-- Attribute selectors for database objects. -/
  instance : DBModel G Attr Obj where
    get := (fun (o : Obj) (a : Attr) =>
        match a with
        | .size => o.size
        | .genus => o.genus
    )

  /-- The database. Query execution filters the database. -/
  instance : DB G Op Pred Attr Obj where
    exec := (fun (q : Query G Op Pred Attr) =>
        pasture.filter (q.interpret G Op Pred Attr Obj)
    )
    correct := by
      intro q
      grind

end MyDB

section Example
  /-! Usage examples. Note that writing queries by hand is quite
      annoying at present, but we shall improve this bit. -/
  open Peano
  open MyDB

  -- query: objects of size 10 whose first component of genus is even
  def my_query : Query G Op Pred Attr :=
    .conj
      (.pred .eq (.pair (.get Attr.size) (.app (Op.const 10) .tt)))
      (.pred .even (.fst (.get Attr.genus)))

  def exec := DB.exec (G := G) (Op := Op) (Pred := Pred) (Attr := Attr) (Model := Obj)

  #eval exec my_query

  #eval exec (.true)

  #eval exec (.false)

end Example
