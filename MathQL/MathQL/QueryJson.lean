import MathQL.Input
import MathQL.Parsing
import Lean.Data.Json

/-! Decoding a query from its JSON form, the shape used over the MCP interface:
`{ "domains": [[v,d],…], "output": ["x.l",…], "condition": "…",
   "order": [["e","asc"],…], "limit": n }`.

The leaf instances below are where the expression parser runs and identifiers are
validated; the `Query` decoder is then derived, composing them. `condition`,
`order`, and `limit` are optional (their structure defaults apply). -/

namespace MathQL.Input

open Lean (Json FromJson fromJson?)

instance : FromJson Expr where
  fromJson? j := j.getStr? >>= Parsing.parseExpr

instance : FromJson Direction where
  fromJson? j := do
    match (← j.getStr?) with
    | "asc" => return .asc
    | "desc" => return .desc
    | s => throw s!"order direction must be \"asc\" or \"desc\", got \"{s}\""

instance : FromJson OutputItem where
  fromJson? j := do
    let (var, field) ← Parsing.parseOutputItem (← j.getStr?)
    return { var, field }

instance : FromJson Binding where
  fromJson? j := do
    match (← j.getArr?).toList with
    | [v, d] =>
      let var ← Parsing.parseIdent (← v.getStr?)
      let domain ← Parsing.parseIdent (← d.getStr?)
      return { var, domain }
    | _ => throw "a domain binding must be a [variable, domain] pair"

instance : FromJson OrderEntry where
  fromJson? j := do
    match (← j.getArr?).toList with
    | [e, d] =>
      let expr ← Parsing.parseExpr (← e.getStr?)
      let dir ← fromJson? d
      return { expr, dir }
    | _ => throw "an order entry must be an [expression, direction] pair"

deriving instance FromJson for Query

/-- Decode a query from its JSON form. -/
def Query.fromJson (j : Json) : Except String Query := fromJson? j

end MathQL.Input
