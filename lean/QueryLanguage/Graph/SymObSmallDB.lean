import QueryLanguage.Graph.SymObSmallDBSignature
import SQLite

/-! The concrete database `sqlite/sym-ob-small.db` for the `Graph` query
    language, accessed through the `leanprover/leansqlite` package.

    NOTE: Because of its size, the database file is currently not in the
    repository. You get it from `https://www.andrej.com/tmp/sym-ob-small.db`
    and then put it into `sqlite/sym-ob-small.db` path at top level.

    We *compile* a `Query` into a SQL `WHERE` clause and let SQLite do the
    filtering. This is why we do not instantiate the pure `DB` structure from
    `QueryLanguage.Core` (whose `exec` is a pure function with a correctness
    proof): the database lives behind `IO`, so execution is an `IO` action
    instead. The compiler below is the bridge between the two worlds. -/

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

  /-- Path to the database, relative to the `lean/` package directory
      (where `lake`/the editor runs `#eval`). -/
  def dbPath : System.FilePath := "../sqlite/sym-ob-small.db"

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

  /-- Execute a query: open the database read-only, run the compiled
      `SELECT … FROM graph WHERE <query>`, and collect the matching rows. -/
  def exec (q : Query O P D) : IO (List Obj) := do
    let db ← SQLite.openWith dbPath .readonly
    let stmt ← SQLite.prepare db (explain q)
    return (← collect stmt #[]).toList

end Graph.SymObSmallDB
