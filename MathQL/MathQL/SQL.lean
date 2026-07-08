import MathQL.SQLExpr
import MathQL.Database

namespace MathQL.SQL

/-- A SQL `SELECT` query: the variables it ranges over (each bound to a `Domain`
and used as a table alias), the hoisted joins (table, alias, `ON` condition),
and the boolean condition. The selected columns and the `FROM` clause are
derived from `vars`. -/
structure Query where
  vars : List (Ident × Domain)
  joins : List (String × String × Expr)
  cond : Expr
  limit : Option Nat
  order : List (Expr × Direction)

/-- Render a query to SQLite text, with a bare condition. The `SELECT` columns and
`FROM` tables come from each variable's `Domain`. A hoisted join renders as
`LEFT JOIN`: when it matches no row, its columns are NULL.
TODO: select only the columns the output needs, rather than every column of the
domain. -/
def renderQuery (q : Query) : String :=
  let froms := ", ".intercalate <| q.vars.map fun (x, dom) => s!"{dom.table} AS {x.name}"
  let joins := String.join <| q.joins.map fun (table, alias, condition) =>
                 s!" LEFT JOIN {table} AS {alias} ON {renderExpr condition}"
  let cols  := ", ".intercalate <| q.vars.flatMap fun (x, dom) =>
                 dom.select.map fun c => renderExpr (.col x.name c)
  let order := match q.order with
    | [] => ""
    | es => " ORDER BY " ++ ", ".intercalate (es.map fun (e, d) => s!"{renderExpr e} {renderDir d}")
  let limit := match q.limit with | some n => s!" LIMIT {n}" | none => ""
  s!"SELECT {cols} FROM {froms}{joins} WHERE {renderExpr q.cond}{order}{limit}"

instance : ToString Expr  := ⟨renderExpr⟩
instance : ToString Query := ⟨renderQuery⟩

end MathQL.SQL
