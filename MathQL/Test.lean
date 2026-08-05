import MathQL

open MathQL

/-- `plus : (int, int) → int`. -/
def plus : List Lean.Json → Result Lean.Json
  | [a, b] => do return .num ((← a.getInt?) + (← b.getInt?))
  | _ => throw "plus expects two arguments"

/-- A toy database for exercising the parser, type-checker, and compiler: one
domain `Graph` with a string primary key and three fields, one SQL function registered
under a SQL name of its own, and one postprocessing function. -/
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

/-- String pairs as a JSON array of two-element arrays. -/
def entries (es : List (String × String)) : Lean.Json :=
  .arr (es.map fun (a, b) => Lean.Json.arr #[Lean.Json.str a, Lean.Json.str b]).toArray

/-- A query in JSON form binding `g` and `h` to `Graph`, with the given output
    (alias, expression) pairs and condition. -/
def jq (output : List (String × String)) (condition : String) : Lean.Json :=
  json% {
    "domains":   [["g", "Graph"], ["h", "Graph"]],
    "output":    $(entries output),
    "condition": $(Lean.toJson condition)
  }

/-- A query in JSON form like `jq`, with an ORDER BY clause. -/
def jqOrder (output : List (String × String)) (condition : String)
    (order : List (String × String)) : Lean.Json :=
  json% {
    "domains":   [["g", "Graph"], ["h", "Graph"]],
    "output":    $(entries output),
    "condition": $(Lean.toJson condition),
    "order":     $(entries order)
  }

/-- A query in JSON form like `jq`, with a `postprocess` stage. -/
def jqPost (output : List (String × String)) (condition : String)
    (post : List (String × String)) : Lean.Json :=
  json% {
    "domains":     [["g", "Graph"], ["h", "Graph"]],
    "output":      $(entries output),
    "condition":   $(Lean.toJson condition),
    "postprocess": $(entries post)
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
    `row`, or `none` when type-checking reports an error. -/
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
#guard !elaborates (jq [("n", "g.n")] "g.n")            -- a condition is checked at Bool
#guard !elaborates (jq [("b", "g.bogus")] "g.planar")   -- unknown field
#guard !elaborates (jq [("n", "g.n")] "g.planar + 1")   -- Bool used in arithmetic
#guard !elaborates (jq [("n", "g.n")] "id(g) == 3")     -- `id` yields String, the literal Int
#guard !elaborates (jq [("m", "g.n"), ("k", "m + 1")] "true")  -- one output referring to another

-- Ordering by an output alias, bare and inside an expression.
#guard compiles (jqOrder [("m", "g.n * g.n")] "g.planar" [("m", "desc")])
#guard compiles (jqOrder [("m", "g.n")] "true" [("m + 1", "asc")])

-- `id` is an ordinary identifier: an output column named `id` is orderable.
#guard compiles (jqOrder [("id", "g.n")] "true" [("id", "desc")])

-- The alias renders bare and quoted in ORDER BY.
#guard match renderOf (jqOrder [("m", "g.n")] "true" [("m", "desc")]) with
  | .ok s => s.endsWith "ORDER BY \"m\" DESC"
  | .error _ => false

-- Identifiers are quoted; list comparisons canonicalize both sides through json().
#guard match renderOf (jq [("n", "g.n")] "g.ds == [2, 2]") with
  | .ok s => s.endsWith "WHERE (json(\"g\".\"ds\") = json(json_array(2, 2)))"
  | .error _ => false

-- Function calls.

-- A call compiles to the SQL name registered for it.
#guard match renderOf (jq [("n", "g.n")] "size(g.graph6) > 2") with
  | .ok s => s.endsWith "WHERE (\"length\"(\"g\".\"graph6\") > 2)"
  | .error _ => false

-- A call is an ordinary expression: it nests, and it may be an output column.
#guard compiles (jq [("k", "size(g.graph6)")] "size(g.graph6) > size('ab')")

-- The two function tables are disjoint, so each name is callable on one side
-- only: `size` compiles to SQL, `plus` runs during postprocessing.
#guard !elaborates (jq [("n", "g.n")] "plus(g.n, 1) > 3")
#guard !elaborates (jqPost [("s", "id(g)")] "true" [("k", "size(s)")])

-- Argument types and arity are checked at a call.
#guard !elaborates (jq [("n", "g.n")] "size(g.n) > 2")

-- `foo(3)` parses; the checker looks `foo` up in the SQL function table.
#guard !elaborates (jq [("n", "foo(3)")] "true")

-- Postprocessing.

-- Well-formed stages: an int literal, a bare output reference, a call.
#guard elaborates (jqPost [("n", "g.n")] "true" [("k", "3")])
#guard elaborates (jqPost [("n", "g.n")] "true" [("k", "n")])
#guard elaborates (jqPost [("n", "g.n")] "true" [("k", "plus(n, 1)")])
#guard elaborates (jqPost [("n", "g.n")] "true" [])

-- Sequential (let-chain) scoping: an entry may use any *earlier* entry.
#guard elaborates (jqPost [("n", "g.n")] "true" [("k", "plus(n, 1)"), ("m", "plus(k, 2)")])

-- The checker rejects a forward reference.
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

-- Postprocessing sees the query's output columns; its context holds those columns
-- alone, so `g.n` is an error here.
#guard !elaborates (jqPost [("n", "g.n")] "true" [("k", "g.n")])

-- Both clauses are arrays: the decoder requires an array and reports an object.
#guard !elaborates (json% {
  "domains":     [["g", "Graph"]],
  "output":      [["n", "g.n"]],
  "condition":   "true",
  "postprocess": {"k": "plus(n, 1)"}
})
#guard !elaborates (json% {
  "domains":   [["g", "Graph"]],
  "output":    {"n": "g.n"},
  "condition": "true"
})

-- Output columns keep the order they were written in; `Lean.Json` returns an
-- object's keys sorted.
#guard match renderOf (jq [("zeta", "g.n"), ("alpha", "g.n")] "true") with
  | .ok s => s.startsWith "SELECT \"g\".\"n\" AS \"zeta\", \"g\".\"n\" AS \"alpha\""
  | .error _ => false

-- Postprocess fields are computed after SQL: the rendered SQL selects `"n"` alone.
#guard match renderOf (jqPost [("n", "g.n")] "true" [("k", "plus(n, 1)")]) with
  | .ok s => (s.splitOn "\"k\"").length == 1 && (s.splitOn "\"n\"").length > 1
  | .error _ => false

-- Postprocessing evaluation, over a row supplied directly.

-- A call runs during postprocessing, on the output row.
#guard postOf (jqPost [("n", "g.n")] "true" [("k", "plus(n, 1)")]) [("n", json% 5)]
       == some [("k", json% 6)]

-- Each entry sees the values of the earlier ones.
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

-- `defined` and `undefined` identify a raise with null: a present value is defined,
-- and both a null value and a failed evaluation are undefined.
#guard postOf (jqPost [("n", "g.n")] "true" [("a", "defined n"), ("b", "undefined n")])
         [("n", json% 5)]
       == some [("a", json% true), ("b", json% false)]
#guard postOf (jqPost [("n", "g.n")] "true" [("a", "defined n"), ("b", "undefined n")])
         [("n", Lean.Json.null)]
       == some [("a", json% false), ("b", json% true)]
#guard postOf (jqPost [("n", "g.n")] "true"
         [("a", "defined plus(n, 1)"), ("b", "undefined plus(n, 1)")])
         [("n", json% "not a number")]
       == some [("a", json% false), ("b", json% true)]

-- A null output column is undefined in a postprocess entry, as `IS NULL` finds it
-- in a condition.
#guard postOf (jqPost [("n", "g.n")] "true" [("k", "undefined n")]) [("n", Lean.Json.null)]
       == some [("k", json% true)]

-- SQL expression rendering, printed for review.
#eval IO.println (toString (SQL.Expr.binop .and
  (.compare .gt (.col "g" "num_vertices") (.int 3)) (.col "g" "is_planar")))

def main : IO Unit := pure ()
