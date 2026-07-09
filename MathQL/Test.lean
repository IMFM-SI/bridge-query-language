import MathQL

open MathQL

/-- A toy schema for exercising the parser and type-checker: one domain `Graph`
with a string primary key and two fields. -/
def toyCtx : DomainContext :=
  [(.domain "Graph",
    { inputField := [(.label "graph6", { ty := .string, isPrimary := true }),
                     (.label "n", { ty := .int, isPrimary := false }),
                     (.label "planar", { ty := .bool, isPrimary := false })],
      domainField := [],
      outputField := [.label "n"] })]

/-- A query in JSON form binding `g` and `h` to `Graph`, with the given output
    (alias, expression) pairs and condition. -/
def jq (output : List (String × String)) (condition : String) : Lean.Json :=
  json% {
    "domains":   [["g", "Graph"], ["h", "Graph"]],
    "output":    $(Lean.Json.mkObj (output.map fun (a, e) => (a, Lean.Json.str e))),
    "condition": $(Lean.toJson condition)
  }

/-- Does the JSON query `j` decode and type-check against `toyCtx`? -/
def elaborates (j : Lean.Json) : Bool :=
  (Input.Query.fromJson j |>.bind (checkQuery (Context.empty toyCtx)) |>.toOption).isSome

-- Well-typed queries.
#guard elaborates (jq [("n", "g.n")] "g.planar")
#guard elaborates (jq [("n", "g.n")] "g.n > 3")
#guard elaborates (jq [("a", "g.n"), ("b", "h.n")] "g.n = h.n")
#guard elaborates (jq [("gid", "id(g)")] "id(g) == 'abc'")
#guard elaborates (jq [("n", "g.n")] "defined g.n")
#guard elaborates (jq [("m", "Graph['abc'].n")] "Graph['abc'].n > 3")

-- Ill-typed queries.
#guard !elaborates (jq [("n", "g.n")] "g.n")            -- condition is Int, not Bool
#guard !elaborates (jq [("b", "g.bogus")] "g.planar")   -- unknown field
#guard !elaborates (jq [("n", "g.n")] "g.planar + 1")   -- Bool used in arithmetic
#guard !elaborates (jq [("n", "g.n")] "id(g) == 3")     -- id is String, not Int

-- SQL expression rendering (shown for review, not asserted).
#eval IO.println (toString (SQL.Expr.binop .and
  (.compare .gt (.col "g" "num_vertices") (.int 3)) (.col "g" "is_planar")))

def main : IO Unit := pure ()
