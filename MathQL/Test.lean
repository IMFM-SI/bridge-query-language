import MathQL

open MathQL

/-- A toy schema for exercising the parser and type-checker. -/
def toyCtx : DomainContext :=
  [(.domain "Graph",
    { inputField := [(.label "n", .int), (.label "planar", .bool)],
      outputField := [.label "n"] })]

/-- Does `s` parse and type-check against `toyCtx`? -/
def elaborates (s : String) : Bool :=
  (Parsing.parse s |>.bind (checkQuery toyCtx) |>.toOption).isSome

-- Well-typed queries.
#guard elaborates "{ g.n | g ∈ Graph, g.planar }"
#guard elaborates "{ g.n | g ∈ Graph, g.n > 3 }"
#guard elaborates "{ g.n, g.n | g ∈ Graph }"
#guard elaborates "{ g.n, h.n | g ∈ Graph, h ∈ Graph, g.n = h.n }"
#guard elaborates "{ g.n | g ∈ Graph, defined g.n }"
#guard elaborates "{ g.n | g ∈ Graph, undefined g.planar ∨ g.n > 0 }"

-- Ill-typed queries.
#guard !elaborates "{ g.n | g ∈ Graph, g.n }"           -- condition is Int, not Bool
#guard !elaborates "{ g.bogus | g ∈ Graph, g.planar }"  -- unknown output field
#guard !elaborates "{ g.n | g ∈ Graph, g.planar + 1 }"  -- Bool used in arithmetic

def main : IO Unit := pure ()
