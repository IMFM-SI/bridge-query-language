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

def GroundModel (Ground : Type) := Ground → Type

/-- Given an interpretation of ground types, we can interpret
    any type (code) as a Lean type. -/
def Ty.interpret {G : Type} (GM : GroundModel G) : Ty G → Type
  | .unit => Unit
  | .ground g => GM g
  | .prod t u => t.interpret GM × u.interpret GM

/-- An operation signature specifies which primitive operations
    can appear in the terms in queries. Typical examples might be
    arithmetical operations.
-/
structure OpSignature (Ground : Type) where
  /-- operation sysmbols -/
  op : Type
  /-- the domain of an operation symbol -/
  dom : op → Ty Ground
  /-- the codomain of an operation symbol -/
  cod : op → Ty Ground

def OpModel {G} (O : OpSignature G) (GM : GroundModel G) :=
  ∀ (f : O.op), (O.dom f).interpret GM → (O.cod f).interpret GM

/-- A predicate signature specifies which primitive predicates
    (relations) can appear in queries. Typical examples might
    be arithmetical comparison `<` and equality `=`.
    Note that each type may be equipped with its own notion of
    equality, but need not to.
-/
structure PredSignature (Ground : Type) where
  /-- predicate symbols -/
  pred : Type
  /-- the domain of a predicate symbol -/
  dom : pred → Ty Ground

def PredModel {G} (P : PredSignature G) (GM : GroundModel G) :=
  ∀ (p : P.pred), (P.dom p).interpret GM → Bool

/-- The capabilities of a database are described by a signature.
    At present we just assume that each entry (mathematical object)
    in the database has some attributes (e.g. columns or views).

    Queries to the database can refer to the attributes as if they
    were 0-ary operations.
 -/
structure DBSignature (G : Type) where
  /-- the attributes -/
  attr : Type
  /-- the type of an attribute -/
  ty : attr → Ty G

structure DBModel {G} (D : DBSignature G) (GM : GroundModel G) where
  Obj : Type
  get : Obj → ∀ (a : D.attr), (D.ty a).interpret GM

/-- The terms that may appear in a query. -/
inductive Tm {G : Type} (O : OpSignature G) (D : DBSignature G) : Ty G → Type where
| tt : Tm O D Ty.unit
| pair : ∀ {A B : Ty G}, Tm O D A → Tm O D B → Tm O D (.prod A B)
| fst : ∀ {A B : Ty G}, Tm O D (.prod A B) → Tm O D A
| snd : ∀ {A B : Ty G}, Tm O D (.prod A B) → Tm O D B
| app : ∀ (f : O.op), Tm O D (O.dom f) → Tm O D (O.cod f)
| get : ∀ (c : D.attr), Tm O D (D.ty c)

def Tm.interpret {G : Type} {O : OpSignature G} {D : DBSignature G}
                {GM : GroundModel G}
                (OM : OpModel O GM)
                (DM : DBModel D GM)
                (obj : DM.Obj)
                {ty : Ty G} :
                Tm O D ty → Ty.interpret GM ty
| .tt => .unit
| .pair s t => (s.interpret OM DM obj, t.interpret OM DM obj)
| .fst t => Prod.fst (t.interpret OM DM obj)
| .snd t => Prod.snd (t.interpret OM DM obj)
| .app f t => OM f (t.interpret OM DM obj)
| .get a => DM.get obj a

/-- A query is a logical formula. -/
inductive Query {G : Type} (O : OpSignature G) (P : PredSignature G) (D : DBSignature G) where
| false : Query O P D
| true : Query O P D
| conj : Query O P D → Query O P D → Query O P D
| pred : ∀ (p : P.pred), Tm O D (P.dom p) → Query O P D

def Query.interpret {G : Type} {O : OpSignature G} {P : PredSignature G} {D : DBSignature G}
                {GM : GroundModel G}
                (OM : OpModel O GM)
                (PM : PredModel P GM)
                (DM : DBModel D GM)
                (obj : DM.Obj) :
                Query O P D → Bool
| .false => Bool.false
| .true => Bool.true
| .conj p q => p.interpret OM PM DM obj && q.interpret OM PM DM obj
| .pred p t => PM p (t.interpret OM DM obj)

/-- A database stores objects of a given type `Obj`. It specifies how
    the attributes are interpreted, and it can execute queries that fetch
    lists of objects. In the future we will likely replace lists with
    a more suitable datastructure, such as a stream or an iterator. -/
structure DB {G : Type} {O : OpSignature G} {P : PredSignature G} (D : DBSignature G)
                {GM : GroundModel G}
                (OM : OpModel O GM)
                (PM : PredModel P GM)
 where
  /-- The type of objects stored in the database -/
  Model : DBModel D GM
  /-- Execute a query and return the list of objects satisfying it -/
  exec : Query O P D → List Model.Obj
  /-- Correctness of queries states: all objects that a query returns satisfy the query -/
  correct : ∀ (q : Query O P D), (exec q).all (q.interpret OM PM Model)

namespace Peano
  /-! An example of a query language that supports natural numbers,
    numeral constants, addition, equality =, the "even" predicate,
    and the attributes `size` and `genus` (this is made up).
  -/

  /-- The only ground type is `.nat` -/
  inductive G where
  | nat : G

  def GM : GroundModel G
  | .nat => Nat

  inductive Op where
  | const : Nat → Op
  | add : Op

  @[reducible]
  def Op.dom : Op → Ty G
  | .const _ => .unit
  | .add => .prod (.ground .nat) (.ground .nat)

  @[reducible]
  def Op.cod : Op → Ty G
  | .const _ => .ground .nat
  | .add => .ground .nat

  @[reducible]
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

  @[reducible]
  def Pred.dom : Pred → Ty G
  | .eq => .prod (.ground .nat) (.ground .nat)
  | .even => .ground .nat

  @[reducible]
  def P : PredSignature G where
    pred := Pred
    dom := Pred.dom

  def PM : PredModel P GM
  | .eq => (fun (p : Nat × Nat) => p.fst = p.snd)
  | .even => (fun (n : Nat) => n.mod 2 = 0)

  inductive Attr where
  | size : Attr
  | genus : Attr

  /-- `size` returns natural numbers and `genus` returns pairs of natural numbers -/
  @[reducible]
  def Attr.ty : Attr → Ty G
  | .size => .ground .nat
  | .genus => .prod (.ground .nat) (.ground .nat)

  @[reducible]
  def D : DBSignature G where
    attr := Attr
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

  def DM : DBModel D GM where
    Obj := Obj
    get := (fun (o : Obj) (a : Attr) =>
        match a with
        | .size => o.size
        | .genus => o.genus
    )

  /-- The database -/
  def Pasture : DB D OM PM where
    Model := DM
    exec := (fun (q : Query O P D) => pasture.filter (q.interpret OM PM DM))
    correct := by
      intro q
      grind

end MyDB

section Example
  /-! Usage examples. Note that writing queries by hand is quite
      annoying at present, but we shall improve this bit. -/

  open Peano
  open MyDB

  def ten :=
    (.app (Op.const 10) .tt : Tm O D _)

  def get_size :=
    (.get Attr.size : Tm O D _)

  def get_genus :=
    (.get Attr.genus : Tm O D _)

  -- query: objects of size 10 whose first component of genus is even
  def my_query : Query O P D :=
    .conj
      (.pred .eq (.pair get_size ten))
      (.pred .even (.fst get_genus))

  #eval Pasture.exec my_query

  #eval Pasture.exec (.true)

  #eval Pasture.exec (.false)

end Example
