import QueryLanguage.Graph.SymObSmallDB

/-! Usage examples for the `Graph` query language. Each query is written in the
    high-level DSL, compiled to SQL, and run against the real database
    `sqlite/sym-ob-small.db` (see `QueryLanguage.Graph.SymObSmallDB`). -/

namespace Graph.Example

  open Graph.Language
  open Graph.SymObSmallDBSignature
  open Graph.SymObSmallDB

  /-- Run a query and print the compiled SQL, the number of matching graphs, and
      one line per graph: its external reference(s), `order` and `size`. -/
  def report (q : Query O P D) : IO Unit := do
    IO.println s!"SQL: {explain q}"
    let rows ← exec q
    IO.println s!"→ {rows.length} graph(s):"
    for g in rows do
      let ref := if g.refs.isEmpty then "(no external reference)" else g.refs
      IO.println s!"    {ref}  order={g.order}  size={g.size}"

  -- graphs of order 4
  def q_order4 : Query O P D :=
    >> get_order == 4 <<
  #eval report q_order4

  -- graphs of order 5 with at most 4 edges
  def q_small : Query O P D :=
    >> (get_order == 5) && (get_size <= 4) <<
  #eval report q_small

  -- sparse graphs: size strictly less than the order
  def q_sparse : Query O P D :=
    >> get_size < get_order <<
  #eval report q_sparse

  -- using addition: order plus size equal to 10
  def q_sum10 : Query O P D :=
    >> get_order + get_size == 10 <<
  #eval report q_sum10

  -- two graphs of order 12, size 24: one has no external reference, the other
  -- carries several (one per source)
  def q_refs_mixed : Query O P D :=
    >> (get_order == 12) && (get_size == 24) <<
  #eval report q_refs_mixed

  -- six graphs of order 16, size 32: a mix of referenced and unreferenced ones
  def q_no_refs : Query O P D :=
    >> (get_order == 16) && (get_size == 32) <<
  #eval report q_no_refs

  -- six graphs of order 16, size 32: a mix of referenced and unreferenced ones
  def q_no_refs_plus : Query O P D :=
    >> (get_order == 9 + 7) && (get_size == 16 + 16) <<
  #eval report q_no_refs_plus

  /-- `q_no_refs` and `q_no_refs_plus` are *semantically* the same query: they
      denote the same predicate. The only difference is that one writes the
      constants `16`/`32` directly while the other writes `9 + 7`/`16 + 16`, and
      those already evaluate (in Lean, via `OM`) to `16`/`32`. So on every
      database object the two queries return the same verdict, and `rfl` suffices. -/
  theorem q_no_refs_eq_q_no_refs_plus {DM : DBModel D GM} (o : DM.Obj) :
      q_no_refs.interpret OM PM DM o = q_no_refs_plus.interpret OM PM DM o :=
    rfl

end Graph.Example
