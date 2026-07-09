import MathQL.Name
import MathQL.Expr
import MathQL.Result
import MathQL.SQL
import MathQL.Database
import MathQL.Query

/-! Compilation of a type-checked query to SQL: scalar expressions compile to SQL
expressions, and domain expressions compile to aliased table rows, hoisted into
shared `LEFT JOIN`s. -/

namespace MathQL

/-- an alias in an SQL query -/
inductive Alias where
  | alias : String → Alias

abbrev Alias.name : Alias → String
  | .alias s => s

/-- The compilation entry of an identifier: a domain variable with its domain,
    or a constant with its SQL literal. -/
inductive ContextEntry where
  | domain : DomainName → ContextEntry
  | const : SQL.Expr → ContextEntry

/-- The resolution context of a compilation. -/
structure SqlCtx where
  /-- The entry of each identifier; earlier entries shadow later ones. -/
  ident : List (Ident × ContextEntry)
  /-- The schema of a domain. -/
  schema : List (DomainName × Schema)

/-- The state of a compilation: the aliases in use, the hoisted joins (table,
    alias, `ON` condition), and the mapping from hoisted domain expressions to
    their alias and domain. -/
structure CompileState where
  /-- Currently used aliases (needed to generate fresh ones)-/
  taken : List Alias
  /-- Current left joins -/
  joins : List (String × Alias × List (String × SQL.Expr))
  /-- Domains that have so far been hoisted to left joins -/
  hoisted : List (Domain × (Alias × DomainName))

abbrev CompileM := StateT CompileState Result

def SqlCtx.getIdent (Γ : SqlCtx) (x : Ident) : CompileM ContextEntry :=
  match Γ.ident.lookup x with
  | some ce => return ce
  | none => throw s!"unknown identifier {x}"

def SqlCtx.getSchema (Γ : SqlCtx) (dn : DomainName) : CompileM Schema :=
  match Γ.schema.lookup dn with
  | none => throw s!"unknown domain name {dn}"
  | some sch => return sch

def SqlCtx.getColumn (Γ : SqlCtx) (dn : DomainName) (l : Label) : CompileM Column := do
  let sch ← Γ.getSchema dn
  match sch.column.lookup l with
  | some c => return c
  | none => throw s!"unknown column {l} in schema {dn}"

def lookupHoist (d : Domain) : CompileM (Option (Alias × DomainName)) := do
  let st ← get
  return st.hoisted.lookup d

def storeHoist (d : Domain) (a : Alias) (dn : DomainName): CompileM Unit := do
  modify fun st => { st with hoisted := (d, (a, dn)) :: st.hoisted }

/-- `stem`, or the first `stemₖ` (k ≥ 2) not in `taken`; `none` if `fuel`
    candidates are all taken. -/
def firstFree (taken : List Alias) (stem : String) : Nat → Nat → Option String
  | 0, _ => none
  | fuel + 1, i =>
    let cand := if i == 0 then stem else s!"{stem}{i + 1}"
    if taken.any fun t => t.name.toLower == cand.toLower
    then firstFree taken stem fuel (i + 1)
    else some cand

/-- A fresh alias formed from `stem`. -/
def freshAlias (stem : String) : CompileM Alias := do
  let st ← get
  match firstFree st.taken stem (st.taken.length + 1) 0 with
  | some name =>
    modify fun st => { st with taken := .alias name :: st.taken }
    return .alias name
  | none => throw "internal error: no fresh alias available"

/-- The stem of the alias of a hoisted domain expression. -/
def domainStem : Domain → String
  | .ident x => x.name
  | .obj d _ => d.name
  | .field e l => domainStem e ++ "_" ++ l.name

def getPrimaryKey (Γ : SqlCtx) (dn : DomainName) : CompileM (List Column) := do
  let sch ← Γ.getSchema dn
  return (sch.column.map Prod.snd).filter Column.isPrimary

def mkJoin (table : String) (stem : String) (eqs : List (String × SQL.Expr))
  : CompileM Alias
  := do
  let alias ← freshAlias stem
  modify (fun st => { st with joins := (table, alias, eqs) :: st.joins })
  return alias

mutual

/-- The alias of the row denoted by a domain expression, and its domain. The
    result for an equal expression is stored and reused. A domain variable is
    its own alias; an `obj` or a domain-valued field is hoisted to a join. -/
def compileDomain (Γ : SqlCtx) (d : Domain) : CompileM (Alias × DomainName) := do
  match d with

  | .ident x => do
    let ce ← Γ.getIdent x
    match ce with
    | .domain d => return (.alias x.name, d)
    | .const _  => throw s!"{x} is not a domain variable"

  | .obj dn es =>
    match (← lookupHoist d) with
    | some r => return r
    | none =>
      let sch ← Γ.getSchema dn
      let ks ← compileExprList Γ es
      let a ← mkJoin sch.table (domainStem d) (List.zip sch.primaryColumns ks)
      storeHoist d a dn
      return (a, dn)

  | .field d' l =>
    match (← lookupHoist d) with
    | some r => return r
    | none =>
      let (a', dn) ← compileDomain Γ d'
      let sch ← Γ.getSchema dn
      let f ← sch.getForeignKey l
      let fsch ← Γ.getSchema f.domain
      let eqs := f.column.map (fun (c, c') => (c', .col a'.name c))
      let a ← mkJoin fsch.table (domainStem d) eqs
      storeHoist d a f.domain
      return (a, f.domain)

termination_by sizeOf d

/-- Compile a scalar expression to a SQL expression. -/
def compileExpr (Γ : SqlCtx) (e : Expr) : CompileM SQL.Expr := do
  match e with
  | .int n => return .int n

  | .bool b => return .bool b

  | .str s => return .str s

  | .ident x =>
    match Γ.ident.lookup x with
    | some (.const s) => return s
    | some (.domain _) => throw s!"{x} is a domain variable, not a value"
    | none => throw s!"unknown constant {x}"

  | .id d =>
    let (alias, dn) ← compileDomain Γ d
    let sch ← Γ.getSchema dn
    return .jsonArray' (sch.primaryColumns.map (fun c => .col alias.name c))

  | .field d l =>
    let (alias, dn) ← compileDomain Γ d
    let f ← Γ.getColumn dn l
    return .col alias.name f.column

  | .unop op e =>
    let s ← compileExpr Γ e
    return .unop op s

  | .binop op e₁ e₂ =>
    let s₁ ← compileExpr Γ e₁
    let s₂ ← compileExpr Γ e₂
    return .binop op s₁ s₂

  | .compare op _ e₁ e₂ =>
    let s₁ ← compileExpr Γ e₁
    let s₂ ← compileExpr Γ e₂
    return .compare op s₁ s₂

  | .ite c a b =>
    let sc ← compileExpr Γ c
    let sa ← compileExpr Γ a
    let sb ← compileExpr Γ b
    return .case sc sa sb

  | .defined (.id d) =>
    let (alias, dn) ← compileDomain Γ d
    let sch ← Γ.getSchema dn
    let pks := sch.primaryColumns
    match pks with
    | [] => return .bool true
    | c :: _ => return .isNotNull (.col alias.name c)

  | .defined e =>
      let s ← compileExpr Γ e
      return .isNotNull s

  | .undefined (.id d)=>
    let (alias, dn) ← compileDomain Γ d
    let sch ← Γ.getSchema dn
    let pks := sch.primaryColumns
    match pks with
    | [] => return .bool true
    | c :: _ => return .isNull (.col alias.name c)

  | .undefined e =>
      let s ← compileExpr Γ e
      return .isNull s

  | .tuple es =>
    let ss ← compileExprList Γ es
    return .jsonArray ss

  | .list es =>
    let ss ← compileExprList Γ es
    return .jsonArray ss

  | .proj e i =>
    let s ← compileExpr Γ e
    return .jsonExtract s i

termination_by sizeOf e

/-- Compile a list of expressions for a `json_array` argument list. -/
def compileExprList (Γ : SqlCtx) : List Expr → CompileM (List SQL.Expr)
  | [] => return []
  | e :: es => do
    let s ← compileExpr Γ e
    let ss ← compileExprList Γ es
    return s :: ss
termination_by es => sizeOf es

end

/-- Compile a type-checked query to a SQL query. -/
def compileQuery (D : Database) (q : Query) : Result SQL.Query := do
  let froms ← q.vars.mapM fun (x, n) =>
    match D.domain.lookup n with
    | some dom => pure (dom.table, x.name)
    | none => throw s!"unknown domain {n}"
  let Γ : SqlCtx :=
    { ident := (q.vars.map fun (x, n) => (x, .domain n)) ++
               (D.const.map fun (x, _, s) => (x, .const s))
      schema := D.domain
    }
  let Δ : SqlCtx :=
    { Γ with ident := (q.output.map fun (x, _, _) => (x, .const (.ref x.name))) ++ Γ.ident }
  let act : CompileM (List (SQL.Expr × String) × SQL.Expr × List (SQL.Expr × Direction)) := do
    let output ← q.output.mapM fun (x, _, e) => do
      let s ← compileExpr Γ e
      return (s, x.name)
    let cond ← compileExpr Γ q.condition
    let order ← q.order.mapM fun ((e, dir) : Expr × Direction) => do
      let s ← compileExpr Δ e
      return (s, dir)
    return (output, cond, order)
  match act.run { taken := q.vars.map fun (x, _) => .alias x.name, joins := [], hoisted := [] } with
  | .error e => throw e
  | .ok ((output, cond, order), st) =>
    let joins := st.joins.reverse.map fun (table, alias, eqs) => (table, alias.name, eqs)
    return { froms, joins, output, cond, order, limit := q.limit }

end MathQL
