import MathQL.Input
import MathQL.Parsing
import Lean.Data.Json

/-! Decoding a query from its JSON form, the shape used over the MCP interface:
`{ "domains": [[v,d],…], "output": [[name,e],…], "condition": "…",
   "order": [["e","asc"],…], "limit": n, "postprocess": [[name,e],…] }`.

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

/-- Decode a clause given as an array of `[name, expression]` pairs. -/
def entriesFromJson (j : Json) : Except String (List (String × Expr)) := do
  let entries ← j.getArr?
  entries.toList.mapM fun entry => do
    match (← entry.getArr?).toList with
    | [n, e] =>
      let nameText ← n.getStr?
      let exprText ← e.getStr?
      let name ← Parsing.parseIdent nameText
      let expr ← Parsing.parseExpr exprText
      return (name, expr)
    | _ => throw "an entry must be a [name, expression] pair"

instance : FromJson Binding where
  fromJson? j := do
    match (← j.getArr?).toList with
    | [v, d] =>
      let varText ← v.getStr?
      let domainText ← d.getStr?
      let var ← Parsing.parseIdent varText
      let domain ← Parsing.parseIdent domainText
      return { var, domain }
    | _ => throw "a domain binding must be a [variable, domain] pair"

instance : FromJson OrderEntry where
  fromJson? j := do
    match (← j.getArr?).toList with
    | [e, d] =>
      let exprText ← e.getStr?
      let expr ← Parsing.parseExpr exprText
      let dir ← fromJson? d
      return { expr, dir }
    | _ => throw "an order entry must be an [expression, direction] pair"

/-- Decode an optional field: absent key yields `none`. -/
private def optField {α} [FromJson α] (j : Json) (key : String) : Except String (Option α) :=
  match j.getObjVal? key with
  | .ok v => (fromJson? v : Except String α).map some
  | .error _ => .ok none

/-- Decode a query from its JSON form. -/
def Query.fromJson (j : Json) : Except String Query := do
  let domainsJ ← j.getObjVal? "domains"
  let domains ← (fromJson? domainsJ : Except String (List Binding))
  let outputJ ← j.getObjVal? "output"
  let output ← entriesFromJson outputJ
  let condition ← optField j "condition"
  let order ← optField j "order"
  let limit ← optField j "limit"
  let postprocess ← match j.getObjVal? "postprocess" with
    | .ok v => entriesFromJson v
    | .error _ => pure []
  return { domains, output, condition, order, limit, postprocess }

end MathQL.Input
