/-!
  This is a core setup for a query language thats acts as an interface between
  Lean and a database. There is no presumption here about how the database is
  implemented, we only assume that it knows how to execute queries.

  The end user would not use these types directly. There will be another layer
  that translates user queries.

  This module is the **generic core**: it is fully parametric in the ground
  types, operations, predicates and attributes. The generic surface DSL lives in
  `QueryLanguage.DSL`, and concrete query languages instantiate it.
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
  /-- Execute a query and return the list of objects satisfying it. Execution
      lives in `IO`, because the database may be an external store. -/
  exec : Query O P D → IO (List Model.Obj)
  /-- Correctness of queries: `exec` returns only objects satisfying the query.
      Since `exec q` is an `IO` action, we cannot inspect its result directly;
      instead we record that it factors as a *raw fetch* from the backing store
      followed by a pure filter by the query's interpretation. Filtering keeps
      exactly the satisfying objects, so every object `exec q` returns satisfies
      `q`. (For an in-memory database the fetch is trivial; for an external one
      it is the underlying query against the store.) -/
  correct : ∀ (q : Query O P D),
    ∃ fetch : IO (List Model.Obj),
      exec q = (List.filter (q.interpret OM PM Model)) <$> fetch
