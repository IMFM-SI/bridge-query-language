import MathQL.Name
import MathQL.Expr
import MathQL.Result
import MathQL.SQL
import MathQL.Database
import MathQL.Query

/-! Compilation of a type-checked query to a SQL query, and of its condition to
a SQL expression. Lists and tuples have no SQL form and are rejected. -/

namespace MathQL

/-- What compiling a condition needs: each `x.label` resolves to a
    `(table-alias, column)`, and each constant to its SQL literal. -/
structure SqlCtx where
  field : Ident → Label → Option (String × String)
  const : Ident → Option SQL.Expr

mutual

/-- Compile a typed condition expression to a SQL expression. -/
def toSQL (Γ : SqlCtx) (e : Expr) : Result SQL.Expr := do
  match e with
  | .int n =>
    return .int n

  | .bool b =>
    return .bool b

  | .str s =>
    return .str s

  | .const x =>
    match Γ.const x with
    | some s => return s
    | none => throw s!"unknown constant {repr x}"

  | .id x d =>
    sorry

  | .field x l =>
    match Γ.field x l with
    | some (table, column) => return .col table column
    | none => throw s!"no column for {repr x}.{repr l}"

  | .unop op e =>
    let s ← toSQL Γ e
    return .unop op s

  | .binop op e₁ e₂ =>
    let s₁ ← toSQL Γ e₁
    let s₂ ← toSQL Γ e₂
    return .binop op s₁ s₂

  | .compare op _ e₁ e₂ =>
    let s₁ ← toSQL Γ e₁
    let s₂ ← toSQL Γ e₂
    return .compare op s₁ s₂

  | .ite c a b =>
    let sc ← toSQL Γ c
    let sa ← toSQL Γ a
    let sb ← toSQL Γ b
    return .case sc sa sb

  | .defined e =>
    let s ← toSQL Γ e
    return .isNotNull s

  | .undefined e =>
    let s ← toSQL Γ e
    return .isNull s

  | .tuple es =>
    let ss ← toSQLList Γ es
    return .jsonArray ss

  | .proj e i =>
    let s ← toSQL Γ e
    return .jsonExtract s i

  | .list es =>
    let ss ← toSQLList Γ es
    return .jsonArray ss

/-- Compile a list of expressions for a `json_array` argument list. -/
def toSQLList (Γ : SqlCtx) : List Expr → Result (List SQL.Expr)
  | [] => return []
  | e :: es => do
    let s ← toSQL Γ e
    let ss ← toSQLList Γ es
    return s :: ss

end

/-- The resolution context for a query whose variables are bound to the given schemas. -/
def SqlCtx.ofVars (D : Database) (vars : List (Ident × Domain)) : SqlCtx where
  field x l :=
    match vars.lookup x with
    | none => none
    | some dom => (dom.inputField.lookup l).map fun f => (x.name, f.column)
  const c := (D.const.lookup c).map Prod.snd

/-- Compile a type-checked query to a SQL query. -/
def compile (D : Database) (q : Query) : Result SQL.Query := do
  let vars ← q.vars.mapM fun (x, n) =>
    match D.domain.lookup n with
    | some dom => pure (x, dom)
    | none => throw s!"unknown domain {repr n}"
  -- The following is hand-roled without using do-notation because of universe levels
  let Γ := SqlCtx.ofVars D vars
  match toSQL Γ q.condition with
  | .error e => throw e
  | .ok cond =>
    match q.order.mapM (fun (e, d) => do return (← toSQL Γ e, d)) with
    | .error e => throw e
    | .ok order => return { vars, cond, order, limit := q.limit }

end MathQL
