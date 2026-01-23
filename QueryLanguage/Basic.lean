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

/-- Given an interpretation of ground types, we can interpret
    any type (code) as a Lean type. -/
def Ty.interpret {G : Type} (I : G → Type) : Ty G → Type
  | .unit => Unit
  | .ground g => I g
  | .prod t u => t.interpret I × u.interpret I

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

/-- The terms that may appear in a query. -/
inductive Tm {G : Type} (O : OpSignature G) (D : DBSignature G): Ty G → Type where
| tt : Tm O D Ty.unit
| pair : ∀ {A B : Ty G}, Tm O D A → Tm O D B → Tm O D (.prod A B)
| fst : ∀ {A B : Ty G}, Tm O D (.prod A B) → Tm O D A
| snd : ∀ {A B : Ty G}, Tm O D (.prod A B) → Tm O D B
| app : ∀ (f : O.op), Tm O D (O.dom f) → Tm O D (O.cod f)
| get : ∀ (c : D.attr), Tm O D (D.ty c)


/-- A query is a logical formula. -/
inductive Query {G : Type} (O : OpSignature G) (P : PredSignature G) (D : DBSignature G) where
| fal : Query O P D
| tru : Query O P D
| conj : Query O P D → Query O P D → Query O P D
| pred : ∀ (p : P.pred), Tm O D (P.dom p) → Query O P D

/-- A database stores objects of a given type `Obj`. It specifies how
    the attributes are interpreted, and it can execute queries that fetch
    lists of objects. In the future we will likely replace lists with
    a more suitable datastructure, such as a stream or an iterator. -/
structure DB {G : Type} (I : G → Type) (O : OpSignature G) (P : PredSignature G) (D : DBSignature G) where
  /-- The type of objects stored in the database -/
  Obj : Type
  /-- For a given object and an attribute, return its value -/
  get : Obj → ∀ (a : D.attr), (D.ty a).interpret I
  /-- Execute a query and return the list of objects satisfying it -/
  exec : Query O P D → List Obj

namespace Peano
  /-! An example of a query language that supports natural numbers,
    numeral constants, addition, equality =, the "even" predicate,
    and the attributes `size` and `genus` (this is made up).
  -/

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

  /-- `size` returns natural numbers and `genus` returns pairs of natural numbers -/
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
  /-! A small database, implemented simply as a list of
      objects. -/

  open Peano

  /-- The database stores a bunch of cows, where each cow
      is given by a list of numbers and a genus. -/
  structure Cow where
    elems : List Nat
    genus : Nat × Nat

  /-- The size of a cow is the length of its list. -/
  def Cow.size (c : Cow) : Nat := c.elems.length

  /-- The information stored in the database. -/
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

  /-- The database -/
  def CowDB : DB Ground.interpret opSignature predSignature dbSignature where
    Obj := Cow
    get := (fun (c : Cow) (a : Attr) => match a with
              | .size => c.size
              | .genus => c.genus
           )
    /- TODO implement this -/
    exec := (fun (q : Query _ _ _) => pasture.filter (fun _ => True) )

end MyDB

section Example
  /-! Usage examples. Note that writing queries by hand is quite
      annoying at present, but we shall improve this bit. -/

  open Peano

  def ten :=
    (.app (Op.const 10) .tt : Tm opSignature dbSignature _)

  def get_size :=
    (.get Attr.size : Tm opSignature dbSignature _)

  def get_genus :=
    (.get Attr.genus : Tm opSignature dbSignature _)

  -- query: objects of size 10 whose first component of genus is even
  example: Query opSignature predSignature dbSignature :=
    .conj
      (.pred .eq (.pair get_size ten))
      (.pred .even (.fst get_genus))


end Example
