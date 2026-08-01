import Lean.Data.Json
import MathQL.Name
import MathQL.Ty

/- Postprocessing functions -/

namespace MathQL

/-- `plus : (int, int) → int`. `getInt?` accepts only exponent-zero numbers,
    which is exactly the representation integers arrive in — `decodeCell` builds
    them with `Lean.toJson i.toInt`. A non-integer argument cannot occur in a
    well-typed query, so it falls through to `.null` like any other mismatch. -/
private def plus : List Lean.Json → Lean.Json
| [a, b] =>
  match a.getInt?, b.getInt? with
  | .ok m, .ok n => .num (m + n)
  | _, _ => .null
| _ => .null

private def minus : List Lean.Json → Lean.Json
| [a, b] =>
  match a.getInt?, b.getInt? with
  | .ok m, .ok n => .num (m - n)
  | _, _ => .null
| _ => .null

/-- `times : (int, int) → int`. -/
private def times : List Lean.Json → Lean.Json
| [a, b] =>
  match a.getInt?, b.getInt? with
  | .ok m, .ok n => .num (m * n)
  | _, _ => .null
| _ => .null

/-- `power : (int, int) → int`, reading the exponent with `getNat?` rather than
    `getInt?`.

    `Int` has `HPow Int Nat Int` and no integer power at a negative exponent, so
    the exponent must be a `Nat`. `Ty` has no natural-number type, so the
    signature can only say `int`: `power(x, -1)` type-checks and is rejected at
    runtime with `.null`. That is the silent-null gap already recorded for
    identifier and function lookup, but now reachable from a *well-typed* query
    rather than only from a broken invariant.

    There is deliberately no bound on the exponent. `Int` is arbitrary precision,
    so `power(2, 1000000000)` will try to build a numeral of gigabyte scale and
    take the process down. If this language is exposed to agents, a cap belongs
    here — but picking one is a policy decision, not a detail. -/
private def power : List Lean.Json → Lean.Json
| [a, b] =>
  match a.getInt?, b.getNat? with
  -- Ascribed `Int`: without it `.num` coerces `m` to `JsonNumber` first and the
  -- exponentiation is looked up as `HPow JsonNumber Nat`, which does not exist.
  | .ok m, .ok n => .num ((m ^ n : Int))
  | _, _ => .null
| _ => .null

def functions : List (Ident × List Ty × Ty × (List Lean.Json → Lean.Json)) :=
[
  (.ident "plus", [.int, .int], .int, plus),
  (.ident "minus", [.int, .int], .int, minus),
  (.ident "times", [.int, .int], .int, times),
  (.ident "power", [.int, .int], .int, power)
]

def functionsTy : List (Ident × (List Ty × Ty)) :=
  functions.map (fun (f, ts, t, _) => (f, (ts, t)))

def functionsImpl : List (Ident × (List Lean.Json → Lean.Json)) :=
  functions.map (fun (f, _, _, impl) => (f, impl))


end MathQL
