import MathQL

open MathQL

/-- `plus : (int, int) → int`. -/
def plus : List Lean.Json → Result Lean.Json
  | [a, b] => do return .num ((← a.getInt?) + (← b.getInt?))
  | _ => throw "plus expects two arguments"

/-- A toy database for exercising the parser, type-checker, and compiler: one
domain `Graph` with a string primary key and three fields, one SQL function whose
SQL name differs from its MathQL name, and one postprocessing function. -/
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
  sqlFunction := [(.ident "size", ([.string], .int), "length")]
  postFunction := [(.ident "plus", ([.int, .int], .int), plus)]
  examples := []

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

/-- Does the JSON query `j` decode and type-check against `toyDB`? -/
def elaborates (j : Lean.Json) : Bool :=
  (Input.Query.fromJson j |>.bind (checkQuery toyDB) |>.toOption).isSome

/-- The SQL text of the JSON query `j` against `toyDB`, or the error. -/
def renderOf (j : Lean.Json) : Except String String :=
  Input.Query.fromJson j |>.bind (checkQuery toyDB)
    |>.bind (compileQuery toyDB) |>.map toString

/-- Does the JSON query `j` decode, type-check, and compile against `toyDB`? -/
def compiles (j : Lean.Json) : Bool :=
  (renderOf j).toOption.isSome

/-- The result of comparing `a` and `b` at type `t`, or `none` if it failed. -/
def comparison (op : ComparisonOp) (t : Ty) (a b : Lean.Json) : Option Lean.Json :=
  (evalComparison op t a b).toOption

/-- The postprocess fields of the JSON query `j`, evaluated over the output row
    `row`, or `none` if `j` does not type-check. -/
def postOf (j : Lean.Json) (row : List (String × Lean.Json)) :
    Option (List (String × Lean.Json)) :=
  (Input.Query.fromJson j |>.bind (checkQuery toyDB) |>.toOption).map fun q =>
    (evalPostprocess
      { ident := row.map fun (r : String × Lean.Json) => (.ident r.1, r.2)
        function := toyDB.postFunction.map fun (f, _, impl) => (f, impl) }
      q.postprocess).map fun (p : Ident × Lean.Json) => (p.1.name, p.2)

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

-- The alias renders bare (but quoted) in ORDER BY.
#guard match renderOf (jqOrder [("m", "g.n")] "true" [("m", "desc")]) with
  | .ok s => s.endsWith "ORDER BY \"m\" DESC"
  | .error _ => false

-- Identifiers are quoted; list comparisons canonicalize both sides through json().
#guard match renderOf (jq [("n", "g.n")] "g.ds == [2, 2]") with
  | .ok s => s.endsWith "WHERE (json(\"g\".\"ds\") = json(json_array(2, 2)))"
  | .error _ => false

-- Function calls.

-- A call compiles to the SQL name registered for it, not to its MathQL name.
#guard match renderOf (jq [("n", "g.n")] "size(g.graph6) > 2") with
  | .ok s => s.endsWith "WHERE (\"length\"(\"g\".\"graph6\") > 2)"
  | .error _ => false

-- A call is an ordinary expression: it nests, and it may be an output column.
#guard compiles (jq [("k", "size(g.graph6)")] "size(g.graph6) > size('ab')")

-- The two function tables are disjoint, so each name is callable on one side
-- only: `size` compiles to SQL, `plus` runs in Lean.
#guard !elaborates (jq [("n", "g.n")] "plus(g.n, 1) > 3")
#guard !elaborates (jqPost [("s", "id(g)")] "true" [("k", "size(s)")])

-- Argument types and arity are checked at a call.
#guard !elaborates (jq [("n", "g.n")] "size(g.n) > 2")

-- `foo(3)` parses; the SQL function table is what rejects it.
#guard !elaborates (jq [("n", "foo(3)")] "true")

-- Postprocessing.

-- Well-formed stages: an int literal, a bare output reference, a call.
#guard elaborates (jqPost [("n", "g.n")] "true" [("k", "3")])
#guard elaborates (jqPost [("n", "g.n")] "true" [("k", "n")])
#guard elaborates (jqPost [("n", "g.n")] "true" [("k", "plus(n, 1)")])
#guard elaborates (jqPost [("n", "g.n")] "true" [])

-- Sequential (let-chain) scoping: an entry may use any *earlier* entry.
#guard elaborates (jqPost [("n", "g.n")] "true" [("k", "plus(n, 1)"), ("m", "plus(k, 2)")])

-- ...but not a later one. Forward references are rejected.
#guard !elaborates (jqPost [("n", "g.n")] "true" [("k", "plus(m, 1)"), ("m", "n")])

-- Shadowing, both cases. `Γ.ident` is seeded with the output fields and grows by
-- one per entry, so a single lookup before binding rejects each of these.
#guard !elaborates (jqPost [("n", "g.n")] "true" [("n", "3")])            -- shadows an output
#guard !elaborates (jqPost [("n", "g.n")] "true" [("k", "3"), ("k", "4")]) -- rebinds an earlier entry

-- Arity.
#guard !elaborates (jqPost [("n", "g.n")] "true" [("k", "plus(1)")])
#guard !elaborates (jqPost [("n", "g.n")] "true" [("k", "plus(1, 2, 3)")])

-- Argument type: `id(g)` is a String, `plus` wants Ints.
#guard !elaborates (jqPost [("s", "id(g)")] "true" [("k", "plus(s, 1)")])

-- Unknown function, and unknown identifier.
#guard !elaborates (jqPost [("n", "g.n")] "true" [("k", "bogus(1, 2)")])
#guard !elaborates (jqPost [("n", "g.n")] "true" [("k", "plus(zzz, 1)")])

-- Postprocessing sees the query's output columns and never its domain variables,
-- since its context carries no domains.
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

-- Postprocessing evaluation, over a row supplied directly.

-- A call runs in Lean, on the output row.
#guard postOf (jqPost [("n", "g.n")] "true" [("k", "plus(n, 1)")]) [("n", json% 5)]
       == some [("k", json% 6)]

-- Each entry sees the values of the earlier ones, not just their types.
#guard postOf (jqPost [("n", "g.n")] "true" [("k", "plus(n, 1)"), ("m", "k * 2")])
         [("n", json% 5)]
       == some [("k", json% 6), ("m", json% 12)]

-- An entry whose evaluation fails becomes null, and null propagates.
#guard postOf (jqPost [("n", "g.n")] "true" [("k", "plus(n, 1)"), ("m", "k * 2")])
         [("n", json% "not a number")]
       == some [("k", Lean.Json.null), ("m", Lean.Json.null)]

-- Comparison is evaluated at the type the term carries, matching what the same
-- expression compiles to in SQL: numeric at int and bool, by code point at
-- string, and by canonical JSON text at list and prod.
#guard comparison .lt .int (.num 2) (.num 10) == some (json% true)
#guard comparison .lt .bool (.bool false) (.bool true) == some (json% true)
#guard comparison .lt .string (.str "Z") (.str "a") == some (json% true)
#guard comparison .gt (.list .int) (json% [2, 2]) (json% [2, 10]) == some (json% true)
#guard comparison .eq (.prod [.int, .string]) (json% [1, "a"]) (json% [1, "a"]) == some (json% true)
#guard comparison .ne (.prod [.int, .string]) (json% [1, "a"]) (json% [1, "b"]) == some (json% true)

-- A null operand makes the comparison null.
#guard comparison .lt .int Lean.Json.null (.num 5) == some Lean.Json.null
#guard comparison .eq .string (.str "a") Lean.Json.null == some Lean.Json.null

-- A comparison at a list type, through the whole postprocess path.
#guard postOf (jqPost [("d", "g.ds")] "true" [("b", "d == [2, 2]")]) [("d", json% [2, 2])]
       == some [("b", json% true)]

-- SQL expression rendering (shown for review, not asserted).
#eval IO.println (toString (SQL.Expr.binop .and
  (.compare .gt (.col "g" "num_vertices") (.int 3)) (.col "g" "is_planar")))

def main : IO Unit := pure ()
