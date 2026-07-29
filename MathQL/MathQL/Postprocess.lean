import Lean.Data.Json
import MathQL.Name
import MathQL.Ty

/- Postprocessing functions -/

namespace MathQL

private def addJsonNumber (a b : Lean.JsonNumber) : Lean.JsonNumber :=
  let e := max a.exponent b.exponent
  ⟨a.mantissa * 10 ^ (e - a.exponent) + b.mantissa * 10 ^ (e - b.exponent), e⟩

private def plus : List Lean.Json → Lean.Json
| [.num a, .num b] => .num (addJsonNumber a b)
| _ => .null

def functions : List (Ident × List Ty × Ty × (List Lean.Json → Lean.Json)) :=
[
  (.ident "plus", [.int, .int], .int, plus)
]

def functionsTy : List (Ident × (List Ty × Ty)) :=
  functions.map (fun (f, ts, t, _) => (f, (ts, t)))

def functionsImpl : List (Ident × (List Lean.Json → Lean.Json)) :=
  functions.map (fun (f, _, _, impl) => (f, impl))


end MathQL
