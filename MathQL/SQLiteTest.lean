import MathQL

/-! TEMPORARY: SQLite execution checks for the M2 refactor (docs/postgresql/IMPLEMENTATION.md):
the SQLite backend and postprocessing run end to end, through `Session.handle` as `mathql` does,
on an in-memory database holding a toy `graph` table. They need no dataset files and no server.
Not a test harness: test layout is undecided. Run from `MathQL/`:

    lake exe sqlitetest

Prints one line per check; exits nonzero on any failure. The toy dataset below is a copy of the
one in `Test.lean`, whose guards cover parsing, checking and compilation. -/

open MathQL

/-- `plus : (int, int) → int`. -/
def plus : List Lean.Json → Result Lean.Json
  | [a, b] => do
    let m ← a.getInt?
    let n ← b.getInt?
    return .num (m + n)
  | _ => throw "plus expects two arguments"

/-- The toy database of `Test.lean`: one domain `Graph` with a string primary key and three
fields, and one postprocessing function. -/
def toyDB : Database where
  overview := "toy"
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
  postFunction := [(.ident "plus", ([.int, .int], .int), plus)]
  examples := []

/-- The toy database's SQLite registrations: one SQL function registered under a SQL name of
its own, and no constants. -/
def toySQLite : SQLite.Registrations where
  function := [(.ident "size", ([.string], .int), "length")]

/-- Failures so far. -/
initialize failures : IO.Ref Nat ← IO.mkRef 0

/-- Answer `request` in `s` and compare the response with `expected`. -/
def expectResponse (s : Session) (name : String) (request expected : Lean.Json) : IO Unit := do
  let got ← s.handle request
  if got == expected then
    IO.println s!"PASS {name}"
  else
    failures.modify (· + 1)
    IO.println s!"FAIL {name}: expected {expected.compress}, got {got.compress}"

def main : IO UInt32 := do
  let db ← _root_.SQLite.openWith ":memory:" { memory := true }
  db.exec "CREATE TABLE graph (graph6 TEXT PRIMARY KEY, n INTEGER, planar INTEGER, ds TEXT)"
  db.exec "INSERT INTO graph VALUES ('A_', 2, 1, '[1,1]'), ('Bw', 3, 1, '[2,2,2]'), \
    ('C~', 4, 1, '[3,3,3,3]'), ('D~{', 5, 0, NULL)"
  let s ← Session.ofSQLite db toyDB toySQLite

  -- DIFFERENCES.md, "Division by zero": SQLite's `/` gives NULL.
  expectResponse s "division by zero in SQL is null"
    (json% {"domains": [], "output": [["value", "1 / 0"]]})
    (json% {"rows": [[["value", null]]]})
  -- DIFFERENCES.md, "Postprocessing is independent".
  expectResponse s "division by zero inside a list: SQL versus postprocessing"
    (json% {"domains": [], "output": [["sql_value", "[1 / 0, 1]"]],
            "postprocess": [["post_value", "[1 / 0, 1]"]]})
    (json% {"rows": [[["sql_value", [null, 1]], ["post_value", null]]]})
  expectResponse s "signed division truncates in SQL and in postprocessing"
    (json% {"domains": [], "output": [["a", "-7 / 2"], ["b", "7 / -2"], ["c", "-7 / -2"]],
            "postprocess": [["pa", "-7 / 2"], ["pc", "-7 / -2"]]})
    (json% {"rows": [[["a", -3], ["b", -3], ["c", 3], ["pa", -3], ["pc", 3]]]})
  -- DIFFERENCES.md, "Comparisons of lists and products": JSON-text comparison.
  expectResponse s "list comparison by JSON text"
    (json% {"domains": [], "output": [["greater", "[2, 2] > [2, 10]"]]})
    (json% {"rows": [[["greater", true]]]})
  -- DIFFERENCES.md, "Booleans nested in lists and products": the recorded SQLite outcome.
  expectResponse s "nested booleans (recorded SQLite behavior)"
    (json% {"domains": [], "output": [["top", "true"], ["lst", "[true, false]"], ["tup", "(true, 3)"]],
            "postprocess": [["p0", "tup.0"]]})
    (json% {"rows": [[["top", true], ["lst", [1, 0]], ["tup", [1, 3]], ["p0", 1]]]})

  -- Domain queries: fields, order, limit, NULL collections, a registered SQL function,
  -- a postprocessing function, and a missing object.
  expectResponse s "fields, order and limit"
    (json% {"domains": [["g", "Graph"]], "output": [["id", "id(g)"], ["n", "g.n"], ["ds", "g.ds"]],
            "condition": "g.planar", "order": [["n", "desc"]], "limit": 2})
    (json% {"rows": [[["id", "C~"], ["n", 4], ["ds", [3, 3, 3, 3]]],
                     [["id", "Bw"], ["n", 3], ["ds", [2, 2, 2]]]]})
  expectResponse s "null collection, SQL function and postprocessing function"
    (json% {"domains": [["g", "Graph"]], "output": [["ds", "g.ds"], ["k", "size(g.graph6)"], ["n", "g.n"]],
            "condition": "!g.planar", "postprocess": [["m", "plus(n, k)"], ["u", "undefined ds"]]})
    (json% {"rows": [[["ds", null], ["k", 3], ["n", 5], ["m", 8], ["u", true]]]})
  expectResponse s "missing object"
    (json% {"domains": [], "output": [["n", "Graph['zz'].n"], ["d", "defined id(Graph['zz'])"]]})
    (json% {"rows": [[["n", null], ["d", false]]]})
  expectResponse s "checking error is a response"
    (json% {"domains": [["g", "Graph"]], "output": [["b", "g.bogus"]]})
    (json% {"error": "domain Graph does not have a field bogus"})
  expectResponse s "describe lists no constants"
    (json% {"describe": true})
    (toyDB.describe [])

  let f ← failures.get
  IO.println s!"{f} execution check failure(s)"
  return if f == 0 then 0 else 1
