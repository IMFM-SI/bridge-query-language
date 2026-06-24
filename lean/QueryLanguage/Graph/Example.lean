import QueryLanguage.Graph.SymObSmallDB

/-! Usage examples for the `Graph` query language. Each query is written in the
    high-level DSL, compiled to SQL, and run against the real database
    `sqlite/sym-ob-small.db` (see `QueryLanguage.Graph.SymObSmallDB`). -/

section Example

  open Graph
  open Graph.SymObSmallDB

  /-- Run a query and print the compiled SQL, the number of matching graphs, and
      one line per graph (its `id`, `order`, `size` and sparse6 encoding). -/
  def report (q : Query O P D) : IO Unit := do
    IO.println s!"SQL: {explain q}"
    let rows ← exec q
    IO.println s!"→ {rows.length} graph(s):"
    for g in rows do
      IO.println s!"    #{g.id}  order={g.order}  size={g.size}  sparse6={g.sparse6}"

  -- graphs of order 4
  def q_order4 : Query O P D := >> get_order == 4 <<
  #eval report q_order4

  -- graphs of order 5 with at most 4 edges
  def q_small : Query O P D := >> (get_order == 5) && (get_size <= 4) <<
  #eval report q_small

  -- sparse graphs: size strictly less than the order
  def q_sparse : Query O P D := >> get_size < get_order <<
  #eval report q_sparse

  -- using addition: order plus size equal to 10
  def q_sum10 : Query O P D := >> get_order + get_size == 10 <<
  #eval report q_sum10

end Example
