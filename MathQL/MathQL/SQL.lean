import MathQL.SQLExpr

namespace MathQL.SQL

/-- A SQL `SELECT` query: the `FROM` tables with their aliases, the hoisted
joins (each a table, its alias, and the columnwise equalities `alias.column =
expr` that form the `ON` condition), the output columns each with its alias, the
boolean condition, the ordering, and the limit. -/
structure Query where
  froms : List (String × String)
  joins : List (String × String × List (String × Expr))
  output : List (Expr × String)
  cond : Expr
  order : List (Expr × Direction)
  limit : Option Nat

/-- Render a query to SQLite text, with a bare condition. Each output column is
rendered as `<expr> AS <alias>`; a hoisted join renders as `LEFT JOIN`, so its
columns are NULL wherever the match is empty.

A query selecting no column renders `SELECT 1`, a query over no table renders
without a `FROM` clause, and a hoisted join over no table renders with
`(SELECT 1)`, a source of one row, to its left. -/
def renderQuery (q : Query) : String :=
  let joins := String.join <| q.joins.map fun ((table, alias, eqs) :
      String × String × List (String × Expr)) =>
    let conds := eqs.map fun (col, e) =>
      s!"{alias}.{renderIdent col} = {renderExpr e}"
    let on := if conds.isEmpty then "1" else " AND ".intercalate conds
    s!" LEFT JOIN {renderIdent table} AS {alias} ON {on}"
  let from_ := match q.froms with
    | [] => if q.joins.isEmpty then "" else " FROM (SELECT 1)"
    | froms => " FROM " ++ ", ".intercalate (froms.map fun ((table, alias) : String × String) =>
        s!"{renderIdent table} AS {alias}")
  let cols := match q.output with
    | [] => "1"
    | output => ", ".intercalate (output.map fun ((e, alias) : Expr × String) =>
        s!"{renderExpr e} AS {alias}")
  let order := match q.order with
    | [] => ""
    | es => " ORDER BY " ++ ", ".intercalate (es.map fun (e, d) => s!"{renderExpr e} {renderDir d}")
  let limit := match q.limit with | some n => s!" LIMIT {n}" | none => ""
  s!"SELECT {cols}{from_}{joins} WHERE {renderExpr q.cond}{order}{limit}"

instance : ToString Expr  := ⟨renderExpr⟩
instance : ToString Query := ⟨renderQuery⟩

end MathQL.SQL
