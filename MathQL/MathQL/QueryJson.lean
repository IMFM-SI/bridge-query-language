import MathQL.Input
import MathQL.Parsing
import Lean.Data.Json

/-! Decoding a query from its JSON form, the shape used over the MCP interface:
`{ "domains": [[v,d],…], "output": {name: e, …}, "condition": "…",
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

/-- The `output` object: each key is a plain identifier aliasing the field, each
    value the expression string it names. -/
def outputFromJson (j : Json) : Except String (List (String × Expr)) := do
  let obj ← j.getObj?
  let kvs : List (String × Json) := obj.toList
  kvs.mapM fun (k, v) => do
    let name ← Parsing.parseIdent k
    let s ← v.getStr?
    let e ← Parsing.parseExpr s
    return (name, e)

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

/-- The `postprocess` stage: an **array** of `[name, expression]` pairs, not an
    object like `output`.

    The two differ because the entries differ. Output columns are independent of
    one another, so their order carries no meaning and an object is the honest
    encoding. Postprocess entries are scoped sequentially, let-chain style — each
    may mention the outputs and any earlier postprocess field — so the order *is*
    part of the meaning. An object could not express it: `Lean.Json` returns an
    object's keys sorted, turning `{zeta, yankee, alpha}` into
    `[alpha, yankee, zeta]` and silently permuting the program.

    Passing an object here therefore fails in `getArr?` rather than being
    accepted in some arbitrary order. -/
def postprocessFromJson (j : Json) : Except String (List (String × PostExpr)) := do
  let entries ← j.getArr?
  entries.toList.mapM fun entry => do
    match (← entry.getArr?).toList with
    | [n, e] =>
      let name ← Parsing.parseIdent (← n.getStr?)
      let expr ← Parsing.parsePostExpr (← e.getStr?)
      return (name, expr)
    | _ => throw "a postprocess entry must be a [name, expression] pair"

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
  let output ← outputFromJson outputJ
  let condition ← optField j "condition"
  let order ← optField j "order"
  let limit ← optField j "limit"
  -- Not `optField`: that decodes through `FromJson`, and the postprocess list is
  -- decoded positionally rather than by an instance. Absent means no stage at all.
  let postprocess ← match j.getObjVal? "postprocess" with
    | .ok v => postprocessFromJson v
    | .error _ => pure []
  return { domains, output, condition, order, limit, postprocess }

end MathQL.Input
