import MathQL

open MathQL

/-- A toy database for exercising the parser, type-checker, and compiler: one
domain `Graph` with a string primary key and two fields. -/
def toyDB : Database where
  overview := "toy"
  const := []
  domain :=
    [(.domain "Graph",
      { table := "graph"
        column :=
          [(.label "graph6", { column := "graph6", ty := .string, isPrimary := true, doc := "" }),
           (.label "n", { column := "n", ty := .int, isPrimary := false, doc := "" }),
           (.label "planar", { column := "planar", ty := .bool, isPrimary := false, doc := "" }),
           (.label "ds", { column := "ds", ty := .list .int, isPrimary := false, doc := "" })]
        foreignKey := []
        doc := "" })]
  examples := []

def toyCtx : DomainContext := toyDB.getDomainContext

/-- A query in JSON form binding `g` and `h` to `Graph`, with the given output
    (alias, expression) pairs and condition. -/
def jq (output : List (String × String)) (condition : String) : Lean.Json :=
  json% {
    "domains":   [["g", "Graph"], ["h", "Graph"]],
    "output":    $(Lean.Json.mkObj (output.map fun (a, e) => (a, Lean.Json.str e))),
    "condition": $(Lean.toJson condition)
  }

/-- A query in JSON form like `jq`, with an ORDER BY clause. -/
def jqOrder (output : List (String × String)) (condition : String)
    (order : List (String × String)) : Lean.Json :=
  json% {
    "domains":   [["g", "Graph"], ["h", "Graph"]],
    "output":    $(Lean.Json.mkObj (output.map fun (a, e) => (a, Lean.Json.str e))),
    "condition": $(Lean.toJson condition),
    "order":     $(Lean.Json.arr (order.map fun (e, d) =>
                     Lean.Json.arr #[Lean.Json.str e, Lean.Json.str d]).toArray)
  }

/-- A query in JSON form like `jq`, with a `postprocess` stage. The stage is an
    array, not an object, because its entries are sequentially scoped and their
    order is meaningful. -/
def jqPost (output : List (String × String)) (condition : String)
    (post : List (String × String)) : Lean.Json :=
  json% {
    "domains":     [["g", "Graph"], ["h", "Graph"]],
    "output":      $(Lean.Json.mkObj (output.map fun (a, e) => (a, Lean.Json.str e))),
    "condition":   $(Lean.toJson condition),
    "postprocess": $(Lean.Json.arr (post.map fun (n, e) =>
                       Lean.Json.arr #[Lean.Json.str n, Lean.Json.str e]).toArray)
  }

/-- Does the JSON query `j` decode and type-check against `toyCtx`? -/
def elaborates (j : Lean.Json) : Bool :=
  (Input.Query.fromJson j |>.bind (checkQuery (Context.empty toyCtx)) |>.toOption).isSome

/-- The SQL text of the JSON query `j` against `toyDB`, or the error. -/
def renderOf (j : Lean.Json) : Except String String :=
  Input.Query.fromJson j |>.bind (checkQuery (Context.empty toyCtx))
    |>.bind (compileQuery toyDB) |>.map toString

/-- Does the JSON query `j` decode, type-check, and compile against `toyDB`? -/
def compiles (j : Lean.Json) : Bool :=
  (renderOf j).toOption.isSome

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
#guard !elaborates (jq [("m", "g.n"), ("k", "m + 1")] "true")  -- one output referring to another

-- Ordering by an output alias, bare and inside an expression.
#guard compiles (jqOrder [("m", "g.n * g.n")] "g.planar" [("m", "desc")])
#guard compiles (jqOrder [("m", "g.n")] "true" [("m + 1", "asc")])

-- `id` is an ordinary identifier: an output column named `id` is orderable.
#guard compiles (jqOrder [("id", "g.n")] "true" [("id", "desc")])

-- `foo(3)` is not syntax; only `id(e)` is.
#guard !elaborates (jq [("n", "foo(3)")] "true")

-- The alias renders bare (but quoted) in ORDER BY.
#guard match renderOf (jqOrder [("m", "g.n")] "true" [("m", "desc")]) with
  | .ok s => s.endsWith "ORDER BY \"m\" DESC"
  | .error _ => false

-- Identifiers are quoted; list comparisons canonicalize both sides through json().
#guard match renderOf (jq [("n", "g.n")] "g.ds == [2, 2]") with
  | .ok s => s.endsWith "WHERE (json(\"g\".\"ds\") = json(json_array(2, 2)))"
  | .error _ => false

-- Postprocessing. The only built-in is `plus : (int, int) → int`.

-- Well-formed stages: an int literal, a bare output reference, a call.
#guard elaborates (jqPost [("n", "g.n")] "true" [("k", "3")])
#guard elaborates (jqPost [("n", "g.n")] "true" [("k", "n")])
#guard elaborates (jqPost [("n", "g.n")] "true" [("k", "plus(n, 1)")])
#guard elaborates (jqPost [("n", "g.n")] "true" [])

-- Sequential (let-chain) scoping: an entry may use any *earlier* entry.
#guard elaborates (jqPost [("n", "g.n")] "true" [("k", "plus(n, 1)"), ("m", "plus(k, 2)")])

-- ...but not a later one. Forward references are rejected.
#guard !elaborates (jqPost [("n", "g.n")] "true" [("k", "plus(m, 1)"), ("m", "n")])

-- Arity.
#guard !elaborates (jqPost [("n", "g.n")] "true" [("k", "plus(1)")])
#guard !elaborates (jqPost [("n", "g.n")] "true" [("k", "plus(1, 2, 3)")])

-- Argument type: `id(g)` is a String, `plus` wants Ints.
#guard !elaborates (jqPost [("s", "id(g)")] "true" [("k", "plus(s, 1)")])

-- Unknown function, and unknown identifier.
#guard !elaborates (jqPost [("n", "g.n")] "true" [("k", "bogus(1, 2)")])
#guard !elaborates (jqPost [("n", "g.n")] "true" [("k", "plus(zzz, 1)")])

-- `PostExpr` has no field access by construction: postprocessing sees the query's
-- output columns, never its domain variables.
#guard !elaborates (jqPost [("n", "g.n")] "true" [("k", "g.n")])

-- An object is rejected outright rather than accepted in sorted key order.
#guard !elaborates (json% {
  "domains":     [["g", "Graph"]],
  "output":      {"n": "g.n"},
  "condition":   "true",
  "postprocess": {"k": "plus(n, 1)"}
})

-- Postprocess fields are computed after SQL, so the stage contributes no alias to
-- the query: `"n"` is selected, `"k"` appears nowhere in the rendered SQL.
#guard match renderOf (jqPost [("n", "g.n")] "true" [("k", "plus(n, 1)")]) with
  | .ok s => (s.splitOn "\"k\"").length == 1 && (s.splitOn "\"n\"").length > 1
  | .error _ => false

-- SQL expression rendering (shown for review, not asserted).
#eval IO.println (toString (SQL.Expr.binop .and
  (.compare .gt (.col "g" "num_vertices") (.int 3)) (.col "g" "is_planar")))

def main : IO Unit := pure ()
