import MathQL

open MathQL

/-- A toy schema for exercising the parser and type-checker. -/
def toyDefs : TyDefs :=
  [(.ident "Graph", .record [(.label "n", .int), (.label "planar", .bool)])]

/-- Does `s` parse and type-check against `toyDefs`? -/
def elaborates (s : String) : Bool :=
  (Parsing.parse s |>.bind (checkQuery toyDefs) |>.toOption).isSome

-- Well-typed queries.
#guard elaborates "{ g.n | g ∈ Graph, g.planar }"
#guard elaborates "{ g.n | g ∈ Graph, g.n > 3 }"
#guard elaborates "{ g | g ∈ Graph, g.planar }"

-- Ill-typed queries.
#guard !elaborates "{ g.n | g ∈ Graph, g.n }"           -- condition is Int, not Bool
#guard !elaborates "{ g.bogus | g ∈ Graph, g.planar }"  -- unknown field
#guard !elaborates "{ g.n | g ∈ Graph, g.planar + 1 }"  -- Bool used in arithmetic

def main : IO Unit := pure ()
