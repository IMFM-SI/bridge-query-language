import MathQL.Operators

namespace MathQL.SQL

/-- SQL scalar/boolean expressions. -/
inductive Expr where
  | col       : (table column : String) → Expr
  | int       : Int → Expr
  | str       : String → Expr
  | bool      : Bool → Expr
  | null      : Expr
  | unop      : UnaryOp → Expr → Expr
  | binop     : BinaryOp → Expr → Expr → Expr
  | compare   : ComparisonOp → Expr → Expr → Expr
  | isNull    : Expr → Expr
  | isNotNull : Expr → Expr
  | case      : (cond thn els : Expr) → Expr   -- CASE WHEN cond THEN thn ELSE els END
deriving Repr

/-- The SQL text of a binary operator. -/
def renderBinop : BinaryOp → String
  | .and => "AND" | .or => "OR"
  | .add => "+" | .sub => "-" | .mul => "*"

/-- The SQL text of a comparison operator. -/
def renderCompareOp : ComparisonOp → String
  | .eq => "=" | .ne => "<>" | .lt => "<" | .le => "<=" | .gt => ">" | .ge => ">="

/-- The SQL text of a unary operator. -/
def renderUnop : UnaryOp → String
  | .not => "NOT" | .neg => "-"

/-- Render an expression to SQLite text; string literals are quoted here
(single quotes, `''` escaping an embedded quote). -/
def renderExpr : Expr → String
  | .col table column => s!"{table}.{column}"
  | .int n            => toString n
  | .bool b           => if b then "1" else "0"
  | .str s            => "'" ++ s.replace "'" "''" ++ "'"
  | .null             => "NULL"
  | .unop op e        => s!"{renderUnop op} ({renderExpr e})"
  | .binop op e₁ e₂   => s!"({renderExpr e₁} {renderBinop op} {renderExpr e₂})"
  | .compare op e₁ e₂ => s!"({renderExpr e₁} {renderCompareOp op} {renderExpr e₂})"
  | .isNull e         => s!"({renderExpr e} IS NULL)"
  | .isNotNull e      => s!"({renderExpr e} IS NOT NULL)"
  | .case c t e       => s!"(CASE WHEN {renderExpr c} THEN {renderExpr t} ELSE {renderExpr e} END)"
