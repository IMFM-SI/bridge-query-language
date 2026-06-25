import QueryLanguage.Graph.SymObSmallDBSignature
import SQLite

/-! The concrete database `data/sym-ob-small.db` for the `Graph` query
    language, accessed through the `leanprover/leansqlite` package.

    NOTE: Because of its size, the database file is currently not in the
    repository. You get it from `https://www.andrej.com/tmp/sym-ob-small.db`
    and then put it into `data/sym-ob-small.db` path at top level.

    We *compile* a `Query` into a SQL `WHERE` clause and let SQLite do the
    filtering. Because the database lives behind `IO`, execution is an `IO`
    action; the compiler below is the bridge between the query DSL and SQL.

    This instantiates the generic `DB` structure from `QueryLanguage.Core`,
    whose `exec` is `IO`-valued precisely so that external stores like this one
    fit alongside pure in-memory databases. To satisfy `DB.correct` we do not
    rely on SQLite's `WHERE` for correctness: after fetching the candidate rows
    we *re-filter* them in Lean by the query's interpretation, so that only
    objects satisfying the query are returned and `correct` holds by
    construction (the SQL `WHERE` is then merely an optimisation). -/

namespace Graph.SymObSmallDB

  open Graph.Language Graph.SymObSmallDBSignature

  /-! Compiling queries to SQL

      The `graph` table has columns `"order"` and `size`.

      Note that `order` is a SQL keyword, so it must be quoted as `"order"`. -/

  /-- Compile a (natural-number-valued) term to a SQL scalar expression.

      Only the shapes the DSL can actually produce over this schema occur in
      practice (attributes, numerals and additions of pairs); the remaining
      structural cases are present purely to make the function total. -/
  def Tm.toSQL : {ty : Ty G} → Tm O D ty → String
  | _, .tt                       => "NULL"
  | _, .get Attr.order           => "\"order\""
  | _, .get Attr.size            => "size"
  | _, .app (Op.const n) _       => toString n
  | _, .app Op.add (.pair a b)   => s!"({Tm.toSQL a} + {Tm.toSQL b})"
  | _, .app Op.add t             => s!"({Tm.toSQL t})"
  | _, .fst (.pair a _)          => Tm.toSQL a
  | _, .snd (.pair _ b)          => Tm.toSQL b
  | _, .fst t                    => s!"fst({Tm.toSQL t})"
  | _, .snd t                    => s!"snd({Tm.toSQL t})"
  | _, .pair a b                 => s!"({Tm.toSQL a}, {Tm.toSQL b})"

  /-- Compile a comparison `(a, b)` to `(a <op> b)`. The argument term is the
      pair of operands; `order == 5` builds `Tm.pair (get order) (const 5)`. -/
  def binSQL (t : Tm O D (.prod (.ground .nat) (.ground .nat))) (op : String) : String :=
    s!"({Tm.toSQL (.fst t)} {op} {Tm.toSQL (.snd t)})"

  /-- Compile a query into a SQL boolean expression, suitable for a `WHERE` clause. -/
  def Query.toSQL : Query O P D → String
  | .false           => "0"
  | .true            => "1"
  | .conj p q        => s!"({Query.toSQL p} AND {Query.toSQL q})"
  | .pred Pred.eq t  => binSQL t "="
  | .pred Pred.le t  => binSQL t "<="
  | .pred Pred.lt t  => binSQL t "<"
  | .pred Pred.ge t  => binSQL t ">="
  | .pred Pred.gt t  => binSQL t ">"

  /-! Running queries against the SQLite database -/

  /-- A row fetched for a matching graph: its `order` (number of vertices),
      `size` (number of edges), sparse6 encoding, and external references.

      Rather than the internal database `id`, we report `refs`: the graph's
      entries in the `graphexternalreference` table, aggregated into a single
      comma-separated list of `source:id_source` (e.g. `"HoG:674"`). It is the
      empty string when the graph has no external reference. -/
  structure Obj where
    order   : Int
    size    : Int
    sparse6 : String
    refs    : String
  deriving Repr

  /-- Instantiating the generic `DB` structure.

      Both attributes are natural numbers, so the database model reads `order`
      and `size` off an `Obj` (as `Nat`, via `Int.toNat`; orders/sizes are nats. -/

  def DM : DBModel D GM where
    Obj := Obj
    get := (fun (o : Obj) (a : Attr) =>
        match a with
        | .order => o.order.toNat
        | .size  => o.size.toNat
    )

  /-- Path to the database, relative to the `lean/` package directory
      (where `lake`/the editor runs `#eval`). -/
  def dbPath : System.FilePath := "../data/sym-ob-small.db"

  /-- The full SQL a query compiles to, for inspection. Each matching graph is
      returned once; its external references are pulled from
      `graphexternalreference` (left-joined so graphs with none are still listed)
      and aggregated into a single `source:id_source` list. -/
  def explain (q : Query O P D) : String :=
    "SELECT g.\"order\", g.size, g.graph_in_sparse6, " ++
      "group_concat(r.source || ':' || r.id_source, ', ') AS refs " ++
      "FROM graph g " ++
      "LEFT JOIN graphexternalreference r ON r.graph_id = g.id " ++
      s!"WHERE {Query.toSQL q} GROUP BY g.id"

  /-- Step a prepared `SELECT` to exhaustion, accumulating one `Obj` per row.
      `partial` because the number of result rows is not known statically. -/
  private partial def collect (stmt : SQLite.Stmt) (acc : Array Obj) : IO (Array Obj) := do
    if ← stmt.step then
      let o : Obj := {
        order   := (← stmt.columnInt64 0).toInt
        size    := (← stmt.columnInt64 1).toInt
        sparse6 := (← stmt.columnText 2)
        refs    := (← stmt.columnText 3)
      }
      collect stmt (acc.push o)
    else
      return acc

  /-- Fetch candidate rows: open the database read-only, run the compiled
      `SELECT … FROM graph WHERE <query>`, and collect the resulting rows. -/
  def fetch (q : Query O P D) : IO (List Obj) := do
    let db ← SQLite.openWith dbPath .readonly
    let stmt ← SQLite.prepare db (explain q)
    return (← collect stmt #[]).toList

  /-- Execute a query: `fetch` the candidate rows, then keep only those that
      satisfy the query under its Lean interpretation. The in-Lean filter is
      what makes `DB.correct` provable; SQLite's `WHERE` makes it efficient. -/
  def exec (q : Query O P D) : IO (List Obj) :=
    (List.filter (q.interpret OM PM DM)) <$> fetch q

  /-- The database. `correct` records that `exec` is `fetch` post-filtered by
      the query's interpretation, so every returned object satisfies the query. -/
  def SymObSmall : DB D OM PM where
    Model := DM
    exec := exec
    correct := (fun q => SatisfiesIO.filter (q.interpret OM PM DM) (fetch q))

end Graph.SymObSmallDB
