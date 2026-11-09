import MathQL.Name
import MathQL.Ty
import MathQL.SQLite.SQLExpr

/-! The constants SQLite provides, per dataset: each MathQL name with its type and the SQLite
expression it compiles to. The checker sees the names and types, the compiler the expressions;
both come from these lists. A constant listed here exists on SQLite only (CONST-01). -/

namespace MathQL.SQLite.Constants

/-- The constants of `graphs-small` on SQLite. -/
def graphsSmall : List (Ident × Ty × SQL.Expr) := []

/-- The constants of `sym-ob-small` on SQLite. -/
def symObSmall : List (Ident × Ty × SQL.Expr) := []

end MathQL.SQLite.Constants
