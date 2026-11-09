import MathQL.Name
import MathQL.Ty

/-! The SQL functions SQLite provides, per dataset: each MathQL name with its argument and
result types and the name of the existing SQLite function it calls. The checker sees the
signatures, the compiler the SQL names; both come from these lists. Postprocessing functions
are separate and live in the shared dataset description (FUNC-01, FUNC-02). -/

namespace MathQL.SQLite.Functions

/-- The SQL functions of `graphs-small` on SQLite. -/
def graphsSmall : List (Ident × (List Ty × Ty) × String) := []

/-- The SQL functions of `sym-ob-small` on SQLite. -/
def symObSmall : List (Ident × (List Ty × Ty) × String) := []

end MathQL.SQLite.Functions
