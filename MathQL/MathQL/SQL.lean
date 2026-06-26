import MathQL.SQLExpr
import MathQL.Database

namespace MathQL.SQL

/-- A SQL `SELECT` query: the variables it ranges over (each bound to a `Domain`
and used as a table alias) and the boolean condition. The selected columns and the
`FROM` clause are derived from `vars`. -/
structure Query where
  vars : List (Ident × Domain)
  cond : Expr

/-- Render a query to SQLite text, with a bare condition. The `SELECT` columns and
`FROM` tables come from each variable's `Domain`.
TODO: select only the columns the output needs, rather than every column of the
domain. -/
def renderQuery (q : Query) : String :=
  let froms := ", ".intercalate <| q.vars.map fun (x, dom) => s!"{dom.table} AS {x.name}"
  let cols  := ", ".intercalate <| q.vars.flatMap fun (x, dom) =>
                 dom.select.map fun c => renderExpr (.col x.name c)
  s!"SELECT {cols} FROM {froms} WHERE {renderExpr q.cond}"

instance : ToString Expr  := ⟨renderExpr⟩
instance : ToString Query := ⟨renderQuery⟩

end MathQL.SQL
