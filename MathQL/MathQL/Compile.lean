import MathQL.Name
import MathQL.Expr
import MathQL.Result
import MathQL.SQL
import MathQL.Database
import MathQL.Query

/-! Compilation of a type-checked query to a SQL query.

An expression of domain type compiles to a row of the domain's table,
designated by a table alias. A domain variable is an alias of the `FROM`
clause; every other expression of domain type is hoisted to a `LEFT JOIN` of
the domain's table, and the compilation state maps each hoisted expression to
its alias. The primary key appears in the `ON` condition of a hoisted join,
in comparisons at domain type, in `ORDER BY` keys, and in
`defined`/`undefined` tests. -/

namespace MathQL

/-- The compilation entry of an identifier: a domain variable with its
    domain, or a constant with its SQL literal. -/
inductive ContextEntry where
  | domain : DomainName → ContextEntry
  | const : SQL.Expr → ContextEntry

/-- The resolution context of a compilation. -/
structure SqlCtx where
  /-- The entry of each identifier; earlier entries shadow later ones. -/
  ident : List (Ident × ContextEntry)
  /-- The schema of a domain. -/
  schema : DomainName → Option Schema

/-- The state of a compilation. -/
structure CompileState where
  /-- The aliases in use: the domain variables and the aliases of hoisted joins. -/
  taken : List String
  /-- The mapping from hoisted expressions to their aliases. -/
  hoisted : List (Expr × String)
  /-- The hoisted joins: table, alias, and `ON` condition. -/
  joins : List (String × String × SQL.Expr)

abbrev CompileM := StateT CompileState Result

/-- An alias not in `taken`: `stem` itself, else `stem2`, `stem3`, ….
    Among `taken.length + 2` candidates at least one is free, so `find?`
    succeeds. SQL identifiers are case-insensitive, hence so is the
    comparison. -/
def freshAlias (stem : String) : CompileM String := do
  let st ← get
  let clashes := fun (c : String) => st.taken.any fun t => t.toLower == c.toLower
  let candidates := stem :: (List.range (st.taken.length + 1)).map fun i => s!"{stem}{i + 2}"
  let name := (candidates.find? fun c => !clashes c).getD stem
  modify fun st => { st with taken := name :: st.taken }
  return name

/-- The stem of the alias of a hoisted expression. -/
def aliasStem : Expr → String
  | .ident x => x.name
  | .obj d _ => d.name
  | .field _ e l => aliasStem e ++ "_" ++ l.name
  | _ => "row"

/-- The single primary-key column of domain `d`, read under `alias`. -/
def pkCol (Γ : SqlCtx) (d : DomainName) (alias : String) : Result SQL.Expr := do
  match Γ.schema d with
  | none => throw s!"unknown domain {repr d}"
  | some sch =>
    match sch.primaryKey with
    | [f] => return .col alias f.column
    | _ => throw s!"cannot compile a composite primary key ({repr d})"

mutual

/-- Extend the state with a join of `table` realizing `e` in domain `d`: a
    fresh alias, the join with `ON` condition `pk = key`, and the `hoisted`
    entry for `e`. Returns the alias. -/
def hoist (Γ : SqlCtx) (e : Expr) (d : DomainName) (table : String)
    (key : SQL.Expr) : CompileM String := do
  let alias ← freshAlias (aliasStem e)
  let pk ← pkCol Γ d alias
  modify fun st => { st with
    hoisted := (e, alias) :: st.hoisted
    joins := st.joins ++ [(table, alias, .compare .eq pk key)] }
  return alias

/-- Compile a typed expression to a SQL expression. -/
def toSQL (Γ : SqlCtx) (e : Expr) : CompileM SQL.Expr := do
  match e with
  | .int n => return .int n

  | .bool b => return .bool b

  | .str s => return .str s

  | .ident x =>
    -- a defined constant is replaced by its definition,
    -- a bare domain cannot appear like this, we will not complie this to the PK
    sorry

  | .obj d _ =>
    -- a bare object cannot appear like this, we will not compile this to the PK
    sorry

  | .id d e =>
    -- get the id from d, not from some compilation of e
    sorry

  | .field d e l =>
   -- if e is a domain variable then we may directly project l,
   -- otherwise we hoist, get an alias and project from it,
   -- the hoisting will compile e to place its compiled form into the join
  sorry

  | .unop op e =>
    let s ← toSQL Γ e
    return .unop op s

  | .binop op e₁ e₂ =>
    let s₁ ← toSQL Γ e₁
    let s₂ ← toSQL Γ e₂
    return .binop op s₁ s₂

  | .compare op t e₁ e₂ =>
    match t with
    | .domain d =>
      let s₁ ← keyOf Γ d e₁
      let s₂ ← keyOf Γ d e₂
      return .compare op s₁ s₂
    | _ =>
      let s₁ ← toSQL Γ e₁
      let s₂ ← toSQL Γ e₂
      return .compare op s₁ s₂

  | .ite c a b =>
    let sc ← toSQL Γ c
    let sa ← toSQL Γ a
    let sb ← toSQL Γ b
    return .case sc sa sb

  | .defined e =>
    -- CLAUDE: remove all such special considerations of whether something
    -- has a defined domainOf. This cannot be correct.
    match domainOf Γ e with
    | some d =>
      let k ← keyOf Γ d e
      return .isNotNull k
    | none =>
      let s ← toSQL Γ e
      return .isNotNull s

  | .undefined e =>
    match domainOf Γ e with
    | some d =>
      let k ← keyOf Γ d e
      return .isNull k
    | none =>
      let s ← toSQL Γ e
      return .isNull s

  | .tuple es =>
    let ss ← toSQLList Γ es
    return .jsonArray ss

  | .list es =>
    let ss ← toSQLList Γ es
    return .jsonArray ss

  | .proj e i =>
    let s ← toSQL Γ e
    return .jsonExtract s i

/-- Compile a list of expressions for a `json_array` argument list. -/
def toSQLList (Γ : SqlCtx) : List Expr → CompileM (List SQL.Expr)
  | [] => return []
  | e :: es => do
    let s ← toSQL Γ e
    let ss ← toSQLList Γ es
    return s :: ss

end

/-- Compile a type-checked query to a SQL query. -/
def compile (D : Database) (q : Query) : Result SQL.Query := do
  let vars ← q.vars.mapM fun (x, n) =>
    match D.domain.lookup n with
    | some dom => pure (x, dom)
    | none => throw s!"unknown domain {repr n}"
  let Γ : SqlCtx :=
    { ident :=
        (q.vars.map fun (x, n) => (x, .domain n)) ++
        (D.const.map fun (x, _, s) => (x, .const s))
      schema := fun d =>
        match D.domain.lookup d with
        | some dom => some dom.toSchema
        | none => none }
  let st : CompileState :=
    { taken := q.vars.map fun (x, _) => x.name, hoisted := [], joins := [] }
  -- Hand-rolled matches: binding the Type-1 `vars` in do-notation is a
  -- universe error.
  match (toSQL Γ q.condition).run st with
  | .error e => throw e
  | .ok (cond, st) =>
    match (q.order.mapM fun ((e, dir) : Expr × Direction) => do
            let s ← toSQL Γ e
            return (s, dir)).run st with
    | .error e => throw e
    | .ok (order, st) =>
      return { vars, joins := st.joins, cond, order, limit := q.limit }

end MathQL
