import MathQL.Syntax
import MathQL.Schema

/-! Compilation of a `Query` to SQL plus a plan describing how to read each
result row back into a `Value`. -/

namespace MathQL

/-- How to read a query's returned value out of a result row. -/
inductive Plan where
  | scalar (sql : String) (params : List Param) (kind : ColumnKind)
  | object (attrs : List Attribute)
  | tuple (parts : List Plan)
deriving Inhabited

private def sqlBinop : String → Option String
  | "and" => "AND" | "or" => "OR"
  | "eq" => "=" | "ne" => "<>" | "le" => "<=" | "lt" => "<" | "ge" => ">=" | "gt" => ">"
  | "add" => "+" | "sub" => "-" | "mul" => "*"
  | _ => none

/-- Compile a scalar expression to a SQL fragment with its `?`-parameters. -/
private def compileScalar (d : Domain) : Expr → Except String (String × List Param)
  | .int n => .ok ("?", [.int n])
  | .bool b => .ok ("?", [.int (if b then 1 else 0)])
  | .str s => .ok ("?", [.str s])
  | .var _ => .error "the object itself cannot appear in a condition"
  | .field (.var _) label =>
    match d.find? label with
    | some attr => .ok (attr.column, [])
    | none => .error s!"unknown invariant '{label}' in domain '{d.name}'"
  | .field _ _ => .error "nested field access (joins) is not supported yet"
  | .unop "not" e => do let (s, p) ← compileScalar d e; .ok ("(NOT " ++ s ++ ")", p)
  | .unop "neg" e => do let (s, p) ← compileScalar d e; .ok ("(-" ++ s ++ ")", p)
  | .unop op _ => .error s!"unknown unary operator '{op}'"
  | .binop op l r => do
    let some sym := sqlBinop op | .error s!"unknown operator '{op}'"
    let (ls, lp) ← compileScalar d l
    let (rs, rp) ← compileScalar d r
    .ok (s!"({ls} {sym} {rs})", lp ++ rp)
  | .tuple _ => .error "a tuple cannot appear in a condition"

private def boolOps : List String := ["and", "or", "eq", "ne", "le", "lt", "ge", "gt"]

private def scalarKind (d : Domain) : Expr → ColumnKind
  | .int _ => .int
  | .bool _ => .bool
  | .str _ => .string
  | .field (.var _) l => ((d.find? l).map (·.kind)).getD .int
  | .unop "not" _ => .bool
  | .binop op _ _ => if boolOps.contains op then .bool else .int
  | _ => .int

private def compileReturn (d : Domain) : Expr → Except String Plan
  | .var _ => .ok (.object d.attributes)
  | .tuple items => .tuple <$> items.mapM (compileReturn d)
  | e => do
    let (sql, params) ← compileScalar d e
    .ok (.scalar sql params (scalarKind d e))

def Plan.selectExprs : Plan → List String
  | .scalar sql _ _ => [sql]
  | .object attrs => attrs.map (·.column)
  | .tuple parts => parts.flatMap Plan.selectExprs

def Plan.params : Plan → List Param
  | .scalar _ p _ => p
  | .object _ => []
  | .tuple parts => parts.flatMap Plan.params

/-- The full SQL statement, its parameters, and the row-reading plan. -/
structure Compiled where
  sql : String
  params : List Param
  plan : Plan

def compileQuery (db : Database) (q : Query) : Except String (Domain × Compiled) := do
  let some domain := db.domain? q.domain
    | .error s!"unknown domain '{q.domain}'"
  let plan ← compileReturn domain q.result
  let (whereSql, whereParams) ← match q.condition with
    | some c => compileScalar domain c
    | none => .ok ("1", [])
  let select := ", ".intercalate plan.selectExprs
  let sql := s!"SELECT {select} FROM {domain.table} WHERE {whereSql}"
  .ok (domain, { sql, params := plan.params ++ whereParams, plan })

end MathQL
