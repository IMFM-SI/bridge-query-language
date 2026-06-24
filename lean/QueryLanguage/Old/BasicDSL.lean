import Lean

/-!
  This is a core setup for a query language thats acts as an interface between
  Lean and a database. There is no presumption here about how the database is
  implemented, we only assume that it knows how to execute queries.

  The end user would not use these types directly. There will be another layer
  that translates user queries.

  Everything below is a scaffolding that needs to be fleshed out. (For example,
  there is only conjunction, but it should be easy to add more logic.)

  PS. This is an improved version over Base.lean that uses typeclass resolution
  over unification for figuring out which types subterms should have, and thus
  avoids having to explicitly let-bind more complex subterms for typechecking.
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

/-- Computes the codomain type of an operation via instance resolution.
    The `outParam` ensures `T` is determined by synthesising an instance
    for the *known* `f`, not by unifying against an expected type.  This
    lets `Tm.call f t` elaborate correctly when used inline, because
    by the time instance search runs, the explicit argument `f` is
    already resolved and `O.cod f` can be reduced. -/
class OpCod {G : Type} (O : OpSignature G)
            (f : O.op) (T : outParam (Ty G)) : Prop where
  cod_eq : O.cod f = T

instance {G} {O : OpSignature G} {f : O.op} : OpCod O f (O.cod f) :=
  ⟨rfl⟩

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

/-- Computes the type of a database attribute via instance resolution.
    Mirrors `OpCod`: by the time instance search runs for `Tm.getAttr c`,
    the explicit argument `c` is already resolved, so `D.ty c` reduces
    to the concrete `Ty G` value. -/
class DBAttrTy {G : Type} (D : DBSignature G)
               (c : D.attr) (T : outParam (Ty G)) : Prop where
  ty_eq : D.ty c = T

instance {G} {D : DBSignature G} {c : D.attr} : DBAttrTy D c (D.ty c) :=
  ⟨rfl⟩

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

/-- Call an operation, with output type determined by `OpCod` instance
    resolution rather than by unification.  Because `Tm.call` is a `def`,
    the explicit argument `f` is resolved before the return type is checked,
    so `OpCod O f T` can be synthesised with `f` concrete, yielding the
    fully-reduced `T`.  This makes `Tm.call f t` usable inline in larger
    query expressions without type annotations. -/
def Tm.call {G : Type} {O : OpSignature G} {D : DBSignature G} {T : Ty G}
            (f : O.op) [h : OpCod O f T] (t : Tm O D (O.dom f)) : Tm O D T :=
  h.cod_eq ▸ Tm.app f t

/-- Get a database attribute, with the attribute type determined by
    `DBAttrTy` instance resolution.  Same elaboration-order guarantee as
    `Tm.call`: `c` is resolved before `T` is computed. -/
def Tm.getAttr {G : Type} {O : OpSignature G} {D : DBSignature G} {T : Ty G}
               (c : D.attr) [h : DBAttrTy D c T] : Tm O D T :=
  h.ty_eq ▸ Tm.get c

/-- A query is a logical formula. -/
inductive Query {G : Type} (O : OpSignature G) (P : PredSignature G) (D : DBSignature G) where
| false : Query O P D
| true : Query O P D
| conj : Query O P D → Query O P D → Query O P D
| pred : ∀ (p : P.pred), Tm O D (P.dom p) → Query O P D

def Query.interpret {G : Type} {O : OpSignature G} {P : PredSignature G}
                    {D : DBSignature G} {GM : GroundModel G}
                    (OM : OpModel O GM) (PM : PredModel P GM) (DM : DBModel D GM)
                    (obj : DM.Obj) : Query O P D → Bool
| .false => Bool.false
| .true => Bool.true
| .conj p q => p.interpret OM PM DM obj && q.interpret OM PM DM obj
| .pred p t => PM p (t.interpret OM DM obj)

/-- A database stores objects of a given type `Obj`. It specifies how
    the attributes are interpreted, and it can execute queries that fetch
    lists of objects. In the future we will likely replace lists with
    a more suitable datastructure, such as a stream or an iterator. -/
structure DB {G : Type} {O : OpSignature G} {P : PredSignature G}
             (D : DBSignature G) {GM : GroundModel G}
             (OM : OpModel O GM) (PM : PredModel P GM)
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

  /- Embedding a high-level human-readable and -usable DSL by elaboration -/

  /- Note: This is a simple experiment specialised to the Peano query language.
           For example, for simplicity it inlines Peano's operation and predicate
           symbols. A full-fledged DSL would be parametric in the query language
           it is supposed to elaborate to. This will need some extensions to the
           definition of the query language as well because operations and
           predicates should come with their corresponsing syntax definitions,
           and the elaboration procedure needs to be parametric in them.
  -/

  namespace Elaboration

    open Lean Elab Meta

    -- declare_syntax_cat query_op   -- currently inlined below for simple experiment

    -- declare_syntax_cat query_attr -- currently inlined below for simple experiment

    -- declare_syntax_cat query_pred -- currently inlined below for simple experiment

    declare_syntax_cat query_tm
    syntax "()"                          : query_tm
    syntax query_tm "," query_tm         : query_tm
    syntax "fst" query_tm                : query_tm
    syntax "snd" query_tm                : query_tm
    -- inlining operations for this example [START]
    syntax num                           : query_tm
    syntax query_tm "+" query_tm         : query_tm
    -- inlining operations for this example [END]
    -- inlining attributes for this example [START]
    syntax "get_size"                    : query_tm
    syntax "get_genus"                   : query_tm
    -- inlining attributes for this example [END]
    syntax "(" query_tm ")"              : query_tm

    declare_syntax_cat query_query
    syntax "false"                      : query_query
    syntax "true"                       : query_query
    syntax query_query "&&" query_query : query_query
    -- inlining predicate symbols for this example [START]
    syntax query_tm "==" query_tm       : query_query
    syntax "even" query_tm              : query_query
    -- inlining predicate symbols for this example [END]
    syntax "(" query_query ")"          : query_query

    -- elaborating DSL terms into Tm expressions
    partial def elabTm : Syntax → MetaM Expr
    | `(query_tm| ()) =>
      mkAppOptM ``Tm.tt  #[some (mkConst ``G), some (mkConst ``O), some (mkConst ``D)]
    | `(query_tm| $t:query_tm , $u:query_tm) => do
      let l ← elabTm t
      let r ← elabTm u
      mkAppM ``Tm.pair  #[l, r]
    | `(query_tm| fst $t:query_tm) => do
      let u ← elabTm t
      mkAppM ``Tm.fst  #[u]
    | `(query_tm| snd $t:query_tm) => do
      let u ← elabTm t
      mkAppM ``Tm.snd  #[u]
    | `(query_tm| $n:num) => do
      let op ← mkAppM ``Op.const #[mkNatLit n.getNat]
      let t ← mkAppOptM ``Tm.tt  #[some (mkConst ``G), some (mkConst ``O), some (mkConst ``D)]
      mkAppOptM ``Tm.call  #[some (mkConst ``G), some (mkConst ``O), some (mkConst ``D), none, some op, none, some t]
    | `(query_tm| $t:query_tm + $u:query_tm) => do
      let l ← elabTm t
      let r ← elabTm u
      let p ← mkAppM ``Tm.pair  #[l, r]
      mkAppOptM ``Tm.call  #[some (mkConst ``G), some (mkConst ``O), some (mkConst ``D), none, some (mkConst ``Op.add), none, some p]
    | `(query_tm| get_size) => do
      mkAppOptM ``Tm.get  #[some (mkConst ``G), some (mkConst ``O), some (mkConst ``D), some (mkConst ``Attr.size)]
    | `(query_tm| get_genus) => do
      mkAppOptM ``Tm.get  #[some (mkConst ``G), some (mkConst ``O), some (mkConst ``D), some (mkConst ``Attr.genus)]
    | `(query_tm| ($t:query_tm)) => elabTm t
    | _ => throwUnsupportedSyntax

    elab "test_elabTm " t:query_tm : term => elabTm t

    #reduce test_elabTm ()
    #reduce test_elabTm (() , ())
    #reduce test_elabTm (fst (() , ()))
    #reduce test_elabTm (4)
    #reduce test_elabTm (42)
    #reduce test_elabTm (() , 42)
    #reduce test_elabTm (24 + 42)
    #reduce test_elabTm (get_size)
    #reduce test_elabTm (get_genus)

    -- elaborating DSL queries into Query expressions
    partial def elabQuery : Syntax → MetaM Expr
    | `(query_query| false) =>
      mkAppOptM ``Query.false  #[some (mkConst ``G), some (mkConst ``O), some (mkConst ``P), some (mkConst ``D)]
    | `(query_query| true) =>
      mkAppOptM ``Query.true  #[some (mkConst ``G), some (mkConst ``O), some (mkConst ``P), some (mkConst ``D)]
    | `(query_query| $t:query_query && $u:query_query) => do
      let l ← elabQuery t
      let r ← elabQuery u
      mkAppM ``Query.conj  #[l, r]
    | `(query_query| $t:query_tm == $u:query_tm) => do
      let l ← elabTm t
      let r ← elabTm u
      let p ← mkAppM ``Tm.pair  #[l, r]
      mkAppOptM ``Query.pred  #[some (mkConst ``G), some (mkConst ``O), some (mkConst ``P), some (mkConst ``D), some (mkConst ``Pred.eq), some p]
    | `(query_query| even $t:query_tm) => do
      let u ← elabTm t
      mkAppOptM ``Query.pred  #[some (mkConst ``G), some (mkConst ``O), some (mkConst ``P), some (mkConst ``D), some (mkConst ``Pred.even), some u]
    | `(query_query| ($t:query_query)) => elabQuery t
    | _ => throwUnsupportedSyntax

    elab "test_elabQuery " q:query_query : term => elabQuery q

    #reduce test_elabQuery false
    #reduce test_elabQuery true
    #reduce test_elabQuery true && false
    #reduce test_elabQuery 2 == 2
    #reduce test_elabQuery (even 2)

    -- high-level syntax for writing terms in the DSL
    elab ">>" t:query_tm "<<" : term => elabTm t

    -- high-level syntax for writing queries in the DSL
    elab ">>" q:query_query "<<" : term => elabQuery q

  end Elaboration

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

  -- query: objects of size 10 whose first component of genus is even
  def my_query : Query O P D :=
    .conj
      (.pred .eq (.pair (.getAttr .size) (.call (.const 10) .tt)))
      (.pred .even (.fst (.getAttr .genus)))

  #eval Pasture.exec my_query

  -- query: objects of size 10 whose first component of genus is even,
  --        written using a high-level domain specific language (DSL)
  def my_query_dsl : Query O P D :=
    >>
    (get_size == 10)
    &&
    (even (fst (get_genus)))
    <<

  #eval Pasture.exec my_query_dsl

  -- both queries produce the same result
  theorem equal_results : my_query = my_query_dsl := by rfl

end Example
