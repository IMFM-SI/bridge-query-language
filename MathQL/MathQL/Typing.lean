import MathQL.Input
import MathQL.Result
import MathQL.Context
import MathQL.Expr
import MathQL.Rules
import MathQL.Query

namespace MathQL

mutual

/-- Check that `e` elaborates to a typed expression of type `t` in context `Γ`.
    Checking forms are handled here; inferring forms delegate to `infer`. -/
def check (Γ : Context) (e : Input.Expr) (t : Ty) : Result { e' : Expr // ExprOfTy Γ e' t } :=
  match e with

  | .nil | .listLit [] =>
    match t with
    | .list _ => .ok ⟨.nil, .nil⟩
    | _ => throw s!"expected {repr t}, but got a list"

  | .ite e₁ e₂ e₃ => do
    let ⟨c, hc⟩ ← check Γ e₁ .bool
    let ⟨a, ha⟩ ← check Γ e₂ t
    let ⟨b, hb⟩ ← check Γ e₃ t
    return ⟨.ite c a b, .ite hc ha hb⟩

  | .tuple es =>
    match t with
    | .prod ts => do
      let ⟨es', h⟩ ← checkTuple Γ es ts
      return ⟨.tuple es', .tuple h⟩
    | _ => throw s!"expected {repr t}, but got a tuple"

  | e => do
    let ⟨t', e', h⟩ ← infer Γ e
    if heq : t' == t then .ok ⟨e', Ty.eq_of_beq t' t heq ▸ h⟩
    else throw s!"type mismatch: expected {repr t}, but got {repr t'}"

/-- Infer a type for `e` in context `Γ`, elaborating it to a typed expression.
    Inferring forms are handled here; checking-only forms are an error. -/
def infer (Γ : Context) (e : Input.Expr) : Result (Σ (t : Ty), { e' : Expr // ExprOfTy Γ e' t }) :=
  match e with

  | .int n => .ok ⟨.int, .int n, .int⟩

  | .bool b => .ok ⟨.bool, .bool b, .bool⟩

  | .str s => .ok ⟨.string, .str s, .str⟩

  | .const x' =>
    let x := .ident x'
    match h : Γ.lookupConst x with
    | some t => .ok ⟨t, .const x, .const h⟩
    | none => throw s!"unbound constant '{x'}'"

  | .field x' l' =>
    let x := .ident x'
    let l := .label l'
    match h : Γ.lookupInputField x l with
    | some t => return ⟨t, .field x l, .field h⟩
    | none => throw s!"{x'} does not have field '{l'}'"

  | .proj e idx => do
    let ⟨te, e', he⟩ ← infer Γ e
    match te, he with
    | .prod ts, hp =>
      match h : ts[idx]? with
      | some t => .ok ⟨t, .proj e' idx, .proj hp h⟩
      | none => throw s!"projection index {idx} out of range"
    | _, _ => throw "projection of a non-product"

  | .unop op e =>
    match h : unaryTy op with
    | (t₁, t₂) => do
      let ⟨e, he⟩ ← check Γ e t₁
      return ⟨t₂, .unop op e, .unop h he⟩

  | .binop op e₁ e₂ =>
    match h : binaryTy op with
    | (t₁, t₂, t₃) => do
      let ⟨e₁, h₁⟩ ← check Γ e₁ t₁
      let ⟨e₂, h₂⟩ ← check Γ e₂ t₂
      return ⟨t₃, .binop op e₁ e₂, .binop h h₁ h₂⟩

  | .compare op e₁ e₂ => do
    let ⟨t, e₁, h₁⟩ ← infer Γ e₁
    let ⟨e₂, h₂⟩ ← check Γ e₂ t
    return ⟨.bool, .compare op t e₁ e₂, .compare h₁ h₂⟩

  | .defined e => do
    let ⟨_, e, he⟩ ← infer Γ e
    return ⟨.bool, .defined e, .defined he⟩

  | .undefined e => do
    let ⟨_, e', he⟩ ← infer Γ e
    return ⟨.bool, .undefined e', .undefined he⟩

  | .cons e es => do
    let ⟨t, e', he⟩ ← infer Γ e
    let ⟨es', hes⟩ ← check Γ es (.list t)
    return ⟨.list t, .cons e' es', .cons he hes⟩

  | .listLit (e :: es) => do
    let ⟨t, e', he⟩ ← infer Γ e
    let ⟨rest, hrest⟩ ← checkList Γ t es
    return ⟨.list t, .cons e' rest, .cons he hrest⟩

  | .ite e₁ e₂ e₃ => do
    let ⟨c, hc⟩ ← check Γ e₁ .bool
    let ⟨t, a, ha⟩ ← infer Γ e₂
    let ⟨b, hb⟩ ← check Γ e₃ t
    return ⟨t, .ite c a b, .ite hc ha hb⟩

  | .tuple es => do
    let ⟨ts, es', h⟩ ← inferTuple Γ es
    return ⟨.prod ts, .tuple es', .tuple h⟩

  | .nil | .listLit [] =>
    throw "cannot infer the type of this empty list"

/-- Check a tuple's components against the product's component types. -/
def checkTuple (Γ : Context) :
    List Input.Expr → (ts : List Ty) → Result { es' : List Expr // TupleOfTy Γ es' ts }
  | [], [] => .ok ⟨[], .nil⟩

  | e :: es, t :: ts => do
    let ⟨e', he⟩ ← check Γ e t
    let ⟨es', hes⟩ ← checkTuple Γ es ts
    return ⟨e' :: es', .cons he hes⟩

  | [], _ :: _ | _ :: _, [] => throw "tuple has the wrong number of components"

/-- Infer types for a tuple's components. -/
def inferTuple (Γ : Context) :
    List Input.Expr → Result (Σ ts : List Ty, { es' : List Expr // TupleOfTy Γ es' ts })

  | [] =>
    .ok ⟨[], [], .nil⟩

  | e :: es => do
    let ⟨t, e', he⟩ ← infer Γ e
    let ⟨ts, es', hes⟩ ← inferTuple Γ es
    return ⟨t :: ts, e' :: es', .cons he hes⟩

/-- Check each list element against `t`, building a `cons` chain ending in `nil`. -/
def checkList (Γ : Context) (t : Ty) :
    List Input.Expr → Result { e' : Expr // ExprOfTy Γ e' (.list t) }

  | [] =>
    .ok ⟨.nil, .nil⟩

  | e :: es => do
    let ⟨e', he⟩ ← check Γ e t
    let ⟨rest, hrest⟩ ← checkList Γ t es
    return ⟨.cons e' rest, .cons he hrest⟩

end

def checkOutput (Γ : Context) : List (String × Option String) → Result (List (Ident × Option Label))
| [] => return []
| (x', .none) :: xls => do
  let x := Ident.ident x'
  match Γ.lookupVar x with
  | .some _ =>
    let xls ← checkOutput Γ xls
    return (x, .none) :: xls
  | .none => throw s!"unknown variables {x'}"
| (x', .some l') :: xls => do
  let x := .ident x'
  let l := .label l'
  match Γ.isOutputField x l with
  | .none | .some false => throw s!"{x'} does not have output field {l'}"
  | .some true => do
    let xls ← checkOutput Γ xls
    return ((x, l) :: xls)

def checkDomainVars (Γ : Context) (acc : List (Ident × DomainName)) :
    List (String × String) → Result (Context × List (Ident × DomainName))
| [] => return (Γ, acc.reverse)
| (x', n') :: xns => do
  let x := .ident x'
  let n := .domain n'
  match Γ.domain.lookup n with
  | .none => throw s!"unknown domain {n'}"
  | .some d => checkDomainVars (Γ.extend x (.domain d)) ((x, n) :: acc) xns

def checkQuery (Γ : Context) (q : Input.Query) : Result Query := do
  let ⟨output, vars, condition⟩ := q
  let ⟨Γ, vars⟩ ← checkDomainVars Γ [] vars
  let output ← checkOutput Γ output
  let ⟨condition, _⟩ ← check Γ condition .bool
  return { vars, condition, output }

end MathQL
