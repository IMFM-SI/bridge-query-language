import MathQL.Operators

namespace MathQL.SQL

/-- SQL scalar/boolean expressions. -/
inductive Expr where
  | col       : (table column : String) → Expr
  | ref       : String → Expr                  -- an output-column alias; ORDER BY only
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
  | json        : Expr → Expr                  -- json(e), the canonical (minified) text
  | jsonArray   : List Expr → Expr             -- json_array(…)
  | jsonExtract : Expr → Nat → Expr            -- json_extract(e, '$[i]')
deriving Repr

def Expr.jsonArray' : List Expr → Expr
| [e] => e
| es => .jsonArray es

/-- The SQL text of a binary operator. -/
def renderBinop : BinaryOp → String
  | .and => "AND" | .or => "OR"
  | .add => "+" | .sub => "-" | .mul => "*"

/-- The SQL text of a comparison operator. -/
def renderCompareOp : ComparisonOp → String
  | .eq => "=" | .ne => "<>" | .lt => "<" | .le => "<=" | .gt => ">" | .ge => ">="

/-- The SQL text of a sort direction. -/
def renderDir : Direction → String
  | .asc => "ASC" | .desc => "DESC"

/-- The SQL text of a unary operator. -/
def renderUnop : UnaryOp → String
  | .not => "NOT" | .neg => "-"

/-- Render an identifier, double-quoted, an embedded quote doubled. -/
def renderIdent (s : String) : String := "\"" ++ s.replace "\"" "\"\"" ++ "\""

mutual

/-- Render an expression to SQLite text; string literals are quoted here
(single quotes, `''` escaping an embedded quote). -/
def renderExpr : Expr → String
  | .col table column => s!"{renderIdent table}.{renderIdent column}"
  | .ref name         => renderIdent name
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
  | .json e           => s!"json({renderExpr e})"
  | .jsonArray es     => s!"json_array({renderArgs es})"
  | .jsonExtract e i  => s!"json_extract({renderExpr e}, '$[{i}]')"

/-- Render a comma-separated argument list. -/
def renderArgs : List Expr → String
  | [] => ""
  | [e] => renderExpr e
  | e :: es => renderExpr e ++ ", " ++ renderArgs es

end
