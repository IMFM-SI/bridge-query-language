import QueryLanguage.Peano.ExampleDBSignature

/-! A small concrete database over the `Peano` query language, implemented
    as a list of objects, instantiating the shared attributes and database
    signature `D` from `QueryLanguage.Peano.ExampleDBSignature`. -/

namespace Peano.ExampleDB
  /-! A small database, implemented simply as a list of objects. -/

  open Peano.Language Peano.ExampleDBSignature

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

  /-- Fetch the entire database. For this in-memory database the "fetch" is
      trivial — we just lift the `pasture` list into `IO`. -/
  def fetch : IO (List Obj) := pure pasture

  /-- Execute a query: fetch all objects, then keep those satisfying the query.
      Execution is `IO`-valued only to match the generic `DB` interface. -/
  def exec (q : Query O P D) : IO (List Obj) :=
    (List.filter (q.interpret OM PM DM)) <$> fetch

  /-- The database. `correct` records that `exec` is `fetch` post-filtered by
      the query's interpretation, so every returned object satisfies the query. -/
  def Pasture : DB D OM PM where
    Model := DM
    exec := exec
    correct := (fun _ => ⟨fetch, rfl⟩)

end Peano.ExampleDB
