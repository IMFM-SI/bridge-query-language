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

  | .list es =>
    match t with
    | .list t => do
      let ⟨es, hes⟩ ← checkList Γ t es
      return ⟨.list es, .list hes⟩
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

  | .int n => pure ⟨.int, .int n, .int⟩

  | .bool b => pure ⟨.bool, .bool b, .bool⟩

  | .str s => pure ⟨.string, .str s, .str⟩

  | .ident x' =>
    let x := .ident x'
    match h : Γ.lookupIdent x with
    | some t => pure ⟨t, .ident x, .ident h⟩
    | none => throw s!"unbound constant '{x'}'"

  | .id e => do
    let ⟨d, e, h⟩ ← inferDomain Γ e
    match hd : Γ.lookupDomain d with
    | some dt => pure ⟨dt.idTy, .id d e, .id h hd rfl⟩
    | none => throw s!"unknown domain {repr d}"

  | .field e l' => do
    let l := Label.label l'
    let ⟨d, e, h⟩ ← inferDomain Γ e
    match hd : Γ.lookupDomain d with
    | some dt =>
      match ht : dt.inputField.lookup l with
      | some t => pure ⟨t, .field d e l, .field h hd ht⟩
      | none => throw s!"domain {repr d} does not have field {l'} "
    | none => throw s!"unknown domain {repr d}"

  | .obj d' e => do
    let d := .domain d'
    match hd : Γ.lookupDomain d with
    | some dt =>
      let ⟨e, he⟩ ← check Γ e dt.idTy
      pure ⟨.domain d, .obj d e, .obj hd he⟩
    | none => throw s!"unknown domain {d'}"

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
      pure ⟨t₂, .unop op e, .unop h he⟩

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

  | .list [] => throw "cannot infer the type of this empty list"

  | .list (e :: es) => do
    let ⟨t, e, he⟩ ← infer Γ e
    let ⟨es, hes⟩ ← checkList Γ t es
    return ⟨.list t, .list (e :: es), .list (.cons he hes)⟩

  | .ite e₁ e₂ e₃ => do
    let ⟨c, hc⟩ ← check Γ e₁ .bool
    let ⟨t, a, ha⟩ ← infer Γ e₂
    let ⟨b, hb⟩ ← check Γ e₃ t
    return ⟨t, .ite c a b, .ite hc ha hb⟩

  | .tuple es => do
    let ⟨ts, es', h⟩ ← inferTuple Γ es
    return ⟨.prod ts, .tuple es', .tuple h⟩

def inferDomain (Γ : Context) (e : Input.Expr) :
  Result (Σ (d : DomainName), { e : Expr // ExprOfTy Γ e (.domain d)})
  := do
  let ⟨t, e, h⟩ ← infer Γ e
  match t, h with
  | .domain d, h => return ⟨d, e, h⟩
  | t, _ => throw s!"domain expected but got {repr t}"

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

/-- Check each list element against `t`. -/
def checkList (Γ : Context) (t : Ty) :
    List Input.Expr → Result { es : List Expr // ListOfTy Γ es t }

  | [] =>
    .ok ⟨[], .nil⟩

  | e :: es => do
    let ⟨e, he⟩ ← check Γ e t
    let ⟨es, hes⟩ ← checkList Γ t es
    return ⟨e :: es, .cons he hes⟩

end

def checkOutput (Γ : Context) : List Input.OutputItem → Result (List OutputItem)
| [] => return []
| .ident x' :: items => do
  let x := Ident.ident x'
  match Γ.lookupIdent x with
  | .some (.domain _) =>
    let items ← checkOutput Γ items
    return .ident x :: items
  | _ => throw s!"{x'} is not a domain variable"
| .field x' l' :: items => do
  let x := Ident.ident x'
  let l := Label.label l'
  match Γ.isOutputField x l with
  | .none | .some false => throw s!"{x'} does not have output field {l'}"
  | .some true =>
    let items ← checkOutput Γ items
    return .field x l :: items
| .id x' :: items => do
  let x := Ident.ident x'
  match Γ.lookupIdent x with
  | .some (.domain _) =>
    let items ← checkOutput Γ items
    return .id x :: items
  | _ => throw s!"{x'} is not a domain variable"

def checkDomainVars (Γ : Context) (acc : List (Ident × DomainName)) :
    List (String × String) → Result (Context × List (Ident × DomainName))
| [] => return (Γ, acc.reverse)
| (x', n') :: xns => do
  let x := .ident x'
  let n := .domain n'
  match Γ.domain.lookup n with
  | .none => throw s!"unknown domain {n'}"
  | .some _ => checkDomainVars (Γ.extendIdent x (.domain n)) ((x, n) :: acc) xns

def checkOrder (Γ : Context) :
    List Input.OrderEntry → Result (List (Expr × Direction))
  | [] => return []
  | entry :: rest => do
    let ⟨_, e, _⟩ ← infer Γ entry.expr
    let rest ← checkOrder Γ rest
    return (e, entry.dir) :: rest

def checkQuery (Γ : Context) (q : Input.Query) : Result Query := do
  let ⟨Γ, vars⟩ ← checkDomainVars Γ [] (q.domains.map fun b => (b.var, b.domain))
  let output ← checkOutput Γ q.output
  let ⟨condition, _⟩ ← check Γ (q.condition.getD (.bool true)) .bool
  let order ← checkOrder Γ (q.order.getD [])
  return { vars, condition, output, limit := q.limit, order }

end MathQL
