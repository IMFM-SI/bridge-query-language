import Postgres
import Lean.Data.Json

/-! TEMPORARY: M1 driver checks for the PostgreSQL backend (docs/postgresql/IMPLEMENTATION.md).

Not a test harness. Run against a live server configured through libpq's `PG*` environment
variables, e.g. the container in `docker/postgres/compose.yaml`:

    PGHOST=localhost PGPORT=55432 PGUSER=mathql PGPASSWORD=mathql PGDATABASE=mathql lake exe pgprobe

Prints one line per check and exits nonzero if any check fails. -/

open Postgres

/-- Failures so far. -/
initialize failures : IO.Ref Nat ← IO.mkRef 0

def check (name : String) (ok : Bool) (detail : String := "") : IO Unit := do
  unless ok do failures.modify (· + 1)
  IO.println s!"{if ok then "PASS" else "FAIL"} {name}{if detail.isEmpty then "" else s!" — {detail}"}"

/-- Prepares `sql`, binds `params` as text (`none` binds NULL) and steps to the first row. -/
def query (db : Conn) (sql : String) (params : List (Option String) := []) : IO Stmt := do
  let stmt ← prepare db sql
  for (p, i) in params.zipIdx do
    match p with
    | some v => stmt.bindText (i + 1).toInt32 v
    | none => stmt.bindNull (i + 1).toInt32
  unless ← stmt.step do throw <| IO.userError s!"no row from {sql}"
  return stmt

/-- Decodes a column the way the backend will: SQL NULL to `null`, JSON text through Lean's parser. -/
def jsonColumn (stmt : Stmt) (col : Int32) : IO Lean.Json := do
  if ← stmt.columnIsNull col then return .null
  match Lean.Json.parse (← stmt.columnText col) with
  | .ok j => return j
  | .error e => throw <| IO.userError s!"bad JSON in column {col}: {e}"

/-- Decodes a `bigint` column exactly from its text. -/
def intColumn (stmt : Stmt) (col : Int32) : IO Lean.Json := do
  if ← stmt.columnIsNull col then return .null
  match (← stmt.columnText col).toInt? with
  | some n => return Lean.Json.num n
  | none => throw <| IO.userError s!"not an integer in column {col}"

/-- The SQLSTATE of a failing `action`, or `none` if it succeeds. -/
def sqlstateOf {α : Type} (action : IO α) : IO (Option String) := do
  try discard action; return none
  catch e => return some ((Error.ofIOError? e).map (·.sqlstate) |>.getD s!"(no sqlstate) {e}")

/-- Resident set size of this process in kB, from `/proc/self/status`. -/
def rssKb : IO Nat := do
  let status ← IO.FS.readFile "/proc/self/status"
  let line := (status.splitOn "\n").find? (·.startsWith "VmRSS:") |>.getD ""
  return ((line.drop 6).trimAscii.toString.takeWhile Char.isDigit).toNat!

def main : IO UInt32 := do
  let db ← Postgres.open ""
  let v ← query db "SELECT current_setting('server_version'), version()"
  IO.println s!"server {← v.columnText 0}: {← v.columnText 1}"

  -- Bound parameters with text that would break naive quoting.
  let tricky := "it's \"quoted\" \\ back\\slash, ünïcødé ✓ 🙂"
  let s ← query db "SELECT $1::bigint + 1, $2::text, $3::boolean, $4::boolean"
    [some "41", some tricky, some "true", some "false"]
  check "bound bigint arithmetic" ((← intColumn s 0) == Lean.Json.num 42)
  check "bound text round-trip" ((← s.columnText 1) == tricky)
  check "bound booleans" ((← s.columnText 2) == "t" && (← s.columnText 3) == "f")
    s!"{← s.columnText 2}/{← s.columnText 3}"

  -- bigint range, exactly.
  let maxI : Int := 9223372036854775807
  let minI : Int := -9223372036854775808
  let b ← query db "SELECT $1::bigint, $2::bigint, 9223372036854775807::bigint, (-9223372036854775807 - 1)::bigint"
    [some (toString maxI), some (toString minI)]
  check "bigint max/min via text" ((← intColumn b 0) == .num maxI && (← intColumn b 1) == .num minI)
  check "bigint literals via text" ((← intColumn b 2) == .num maxI && (← intColumn b 3) == .num minI)
  check "bigint via columnInt64" ((← b.columnInt64 0).toInt == maxI && (← b.columnInt64 1).toInt == minI)
  check "bigint overflow is a query error (22003)"
    ((← sqlstateOf (query db "SELECT $1::bigint + 1" [some (toString maxI)])) == some "22003")

  -- NULLs: scalar, bound and JSONB.
  let n ← query db "SELECT NULL::bigint, $1::text, NULL::jsonb, 'null'::jsonb" [none]
  check "SQL NULL columns" ((← n.columnIsNull 0) && (← n.columnIsNull 1) && (← n.columnIsNull 2))
  check "JSON null is not SQL NULL" (!(← n.columnIsNull 3) && (← jsonColumn n 3) == .null)

  -- JSONB to Lean.Json: nesting, nulls, booleans, strings, exact integers at the bigint limits.
  let expected : Lean.Json := .arr #[
    .arr #[], .arr #[.num 1], .arr #[.arr #[.num 2, .num 3], .arr #[]], .null,
    .bool true, .bool false, .str tricky, .num maxI, .num minI, .arr #[.null, .num 1]]
  let lit := expected.compress
  let j ← query db "SELECT $1::jsonb, to_jsonb($2::text), jsonb_typeof($1::jsonb), pg_typeof($1::jsonb)::text"
    [some lit, some lit]
  let got ← jsonColumn j 0
  check "JSONB decodes to expected Lean.Json" (got == expected) got.compress
  check "to_jsonb(text) gives a JSON string, not the array" ((← jsonColumn j 1) == .str lit)
  check "bound $1::jsonb is an array of type jsonb"
    ((← j.columnText 2) == "array" && (← j.columnText 3) == "jsonb")
  let c ← query db "SELECT to_jsonb(ARRAY[to_jsonb(1::bigint), to_jsonb('hello'::text), to_jsonb(TRUE), to_jsonb(ARRAY[]::jsonb[])]::jsonb[])"
  check "TYPE-02 constructor decodes" ((← jsonColumn c 0) ==
    .arr #[.num 1, .str "hello", .bool true, .arr #[]])
  let e ← query db "SELECT ($1::jsonb ->> 7)::bigint, NULLIF($1::jsonb -> 3, 'null'::jsonb), ($1::jsonb ->> 4)::boolean, $1::jsonb ->> 6"
    [some lit]
  check "TYPE-03 projections" ((← intColumn e 0) == .num maxI && (← e.columnIsNull 1)
    && (← e.columnText 2) == "t" && (← e.columnText 3) == tricky)

  -- Error recovery on the same connection, in normal (autocommit) execution.
  check "division by zero fails (22012)" ((← sqlstateOf (query db "SELECT 1::bigint / 0")) == some "22012")
  let ok1 ← query db "SELECT 42::bigint"
  check "query succeeds after a failed query" ((← intColumn ok1 0) == .num 42)
  check "syntax error fails (42601)" ((← sqlstateOf (query db "SELEC 1")) == some "42601")
  check "missing table fails (42P01)" ((← sqlstateOf (query db "SELECT * FROM \"no_such\".\"t\"")) == some "42P01")
  let ok2 ← query db "SELECT 'still fine'::text"
  check "query succeeds after more failures" ((← ok2.columnText 0) == "still fine")

  -- Releasing connections: a connection dropped in Lean closes on the server.
  let app := "mathql-pgprobe-temp"
  do
    let tmp ← Postgres.open s!"application_name={app}"
    discard <| query tmp "SELECT 1"
  let cnt ← query db "SELECT count(*) FROM pg_stat_activity WHERE application_name = $1" [some app]
  check "dropped connection is closed" ((← intColumn cnt 0) == .num 0) s!"{← cnt.columnText 0} remaining"

  -- Releasing results: many ~1 MB results should not grow memory proportionally.
  let big := "SELECT repeat('x', 1000000)"
  for _ in [0:20] do discard <| query db big
  let before ← rssKb
  for _ in [0:500] do
    let r ← query db big
    discard <| r.columnText 0
  let after ← rssKb
  -- 500 retained results would be ~500 MB; allow generous noise.
  check "results are released" (after < before + 50000) s!"RSS {before} kB → {after} kB after 500 × 1 MB results"

  let f ← failures.get
  IO.println s!"{f} failure(s)"
  return if f == 0 then 0 else 1
