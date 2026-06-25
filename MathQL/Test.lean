import MathQL

open MathQL

private def count (q : String) : IO Nat := do
  match ← MathQL.run q with
  | .error e => IO.eprintln s!"error in [{q}]: {e}"; return 0
  | .ok vs => return vs.length

private def check (name : String) (cond : Bool) : IO Bool := do
  IO.println s!"{if cond then "ok  " else "FAIL"}  {name}"
  return cond

def main : IO UInt32 := do
  let mut ok := true
  ok := (← check "all graphs = 13598"
    ((← count "{ g | g ∈ SmallGraphs }") == 13598)) && ok
  ok := (← check "trees = 48"
    ((← count "{ g | g ∈ SmallGraphs, g.is_tree }") == 48)) && ok
  ok := (← check "complete graphs = 8"
    ((← count "{ g | g ∈ SmallGraphs, g.is_connected ∧ g.min_degree = g.num_vertices - 1 }") == 8)) && ok
  ok := (← check "radius < diameter = 8701 (Option columns via NULL)"
    ((← count "{ g | g ∈ SmallGraphs, g.radius < g.diameter }") == 8701)) && ok
  ok := (← check "non-planar = 5617"
    ((← count "{ g | g ∈ SmallGraphs, ¬ g.is_planar }") == 5617)) && ok
  ok := (← check "orientable maniplexes = 13214"
    ((← count "{ m | m ∈ Maniplexes, m.orientable }") == 13214)) && ok
  ok := (← check "polytopal maniplexes = 3528"
    ((← count "{ m | m ∈ Maniplexes, m.polytopality = \"Polytopal\" }") == 3528)) && ok
  let unknown ← MathQL.run "{ g | g ∈ Nope }"
  ok := (← check "unknown domain is rejected" (match unknown with | .error _ => true | _ => false)) && ok
  let bad ← MathQL.run "{ g | g ∈ SmallGraphs, g.no_such_invariant > 1 }"
  ok := (← check "unknown invariant is rejected" (match bad with | .error _ => true | _ => false)) && ok
  if ok then IO.println "\nALL PASS"; return 0
  else IO.eprintln "\nSOME TESTS FAILED"; return 1
