import MathQL

open MathQL

/-- A toy schema for exercising the parser and type-checker. -/
def toyCtx : DomainContext :=
  [(.domain "Graph",
    { inputField := [(.label "n", .int), (.label "planar", .bool)],
      outputField := [.label "n"] })]

/-- A query in JSON form binding `g` and `h` to `Graph`, with the given output
    list and condition. -/
def jq (output : List String) (condition : String) : Lean.Json :=
  json% {
    "domains":   [["g", "Graph"], ["h", "Graph"]],
    "output":    $(Lean.toJson output),
    "condition": $(Lean.toJson condition)
  }

/-- Does the JSON query `j` decode and type-check against `toyCtx`? -/
def elaborates (j : Lean.Json) : Bool :=
  (Input.Query.fromJson j |>.bind (checkQuery (Context.empty toyCtx)) |>.toOption).isSome

-- Well-typed queries.
#guard elaborates (jq ["g.n"] "g.planar")
#guard elaborates (jq ["g.n"] "g.n > 3")
#guard elaborates (jq ["g.n", "g.n"] "true")
#guard elaborates (jq ["g.n", "h.n"] "g.n = h.n")
#guard elaborates (jq ["g.n"] "defined g.n")
#guard elaborates (jq ["g.n"] "undefined g.planar ∨ g.n > 0")

-- Ill-typed queries.
#guard !elaborates (jq ["g.n"] "g.n")            -- condition is Int, not Bool
#guard !elaborates (jq ["g.bogus"] "g.planar")   -- unknown output field
#guard !elaborates (jq ["g.n"] "g.planar + 1")   -- Bool used in arithmetic

-- Lists and tuples type-check.
#guard elaborates (jq ["g.n"] "[g.n, g.n] == [1, 2]")
#guard elaborates (jq ["g.n"] "(g.n, g.planar) == (1, true)")
#guard elaborates (jq ["g.n"] "(g.n, g.planar).0 == g.n")
#guard !elaborates (jq ["g.n"] "(g.n, g.planar) == (g.n, g.n)")   -- product types differ

-- SQL expression rendering (shown for review, not asserted). Query rendering now
-- needs a `Database`, so it is exercised by `Main` against `graphs-small.db`.
#eval IO.println (toString (SQL.Expr.binop .and
  (.compare .gt (.col "g" "num_vertices") (.int 3)) (.col "g" "is_planar")))

def main : IO Unit := pure ()
