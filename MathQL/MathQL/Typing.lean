import MathQL.Input
import MathQL.Context
import MathQL.Expr
import MathQL.Rules

namespace MathQL

abbrev Result := Except String

mutual

/-- Resolve an input type annotation to a core type. -/
def Input.Ty.toCore : Input.Ty → _root_.MathQL.Ty
  | .name n => .name (.ident n)

  | .int => .int

  | .bool => .bool

  | .string => .string

  | .option t => .option t.toCore

  | .list t => .list t.toCore

  | .prod ts => .prod (Input.Ty.toCoreList ts)

def Input.Ty.toCoreList : List Input.Ty → List _root_.MathQL.Ty
  | [] => []

  | t :: ts => t.toCore :: Input.Ty.toCoreList ts

end

mutual

/-- Check that `e` elaborates to a typed expression of type `t` in context `Γ`.
    Checking forms are handled here; inferring forms delegate to `infer`. -/
def check (Γ : Context) (e : Input.Expr) (t : Ty) : Result { e' : Expr // ExprOfTy Γ e' t } :=
  match e with

  | .nil | .listLit [] =>
    match t with
    | .list _ => .ok ⟨.nil, .nil⟩
    | _ => .error s!"expected {repr t}, but got a list"

  | .noneE =>
    match t with
    | .option _ => .ok ⟨.noneE, .noneE⟩
    | _ => .error s!"expected {repr t}, but got an option"

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
    | _ => .error s!"expected {repr t}, but got a tuple"

  | .cases _ _ => sorry

  | .bind _ _ _ => sorry

  | .cons _ _ | .listLit (_ :: _) | .someE _
  | .int _ | .bool _ | .str _ | .enumCtor _ | .var _ | .field _ _ | .proj _ _
  | .unop _ _ | .binop _ _ _ | .ascribe _ _ => do
    let ⟨t', e', h⟩ ← infer Γ e
    if heq : t' == t then .ok ⟨e', Ty.eq_of_beq t' t heq ▸ h⟩
    else .error s!"type mismatch: expected {repr t}, but got {repr t'}"

/-- Infer a type for `e` in context `Γ`, elaborating it to a typed expression.
    Inferring forms are handled here; checking-only forms are an error. -/
def infer (Γ : Context) (e : Input.Expr) : Result (Σ (t : Ty), { e' : Expr // ExprOfTy Γ e' t }) :=
  match e with

  | .int n => .ok ⟨.int, .int n, .int⟩

  | .bool b => .ok ⟨.bool, .bool b, .bool⟩

  | .str s => .ok ⟨.string, .str s, .str⟩

  | .enumCtor c' =>
    let c := .ident c'
    match h : Γ.findEnum c with
    | some n => .ok ⟨.name n, .enum c, .enum h⟩
    | none => .error s!"unknown constructor '.{c'}'"

  | .var x' =>
    let x := .ident x'
    match h : Γ.lookupVar x with
    | some t => .ok ⟨t, .var x, .var h⟩
    | none => .error s!"unbound variable '{x'}'"

  | .field e l' =>
    let l := .label l'
    match h : Γ.findLabel l with
    | some (n, t) => do
      let ⟨e', he⟩ ← check Γ e (.name n)
      return ⟨t, .field e' l, .field h he⟩
    | none => .error s!"unknown field '{l'}'"

  | .proj e idx => do
    let ⟨te, e', he⟩ ← infer Γ e
    match te, he with
    | .prod ts, hp =>
      match h : ts[idx]? with
      | some t => .ok ⟨t, .proj e' idx, .proj hp h⟩
      | none => .error s!"projection index {idx} out of range"
    | _, _ => .error "projection of a non-product"

  | .unop op e =>
    match h : unaryTy op with
    | (t₁, t₂) => do
      let ⟨e', he⟩ ← check Γ e t₁
      return ⟨t₂, .unop op e', .unop h he⟩

  | .binop op e₁ e₂ =>
    match h : binaryTy op with
    | (t₁, t₂, t₃) => do
      let ⟨e₁', h₁⟩ ← check Γ e₁ t₁
      let ⟨e₂', h₂⟩ ← check Γ e₂ t₂
      return ⟨t₃, .binop op e₁' e₂', .binop h h₁ h₂⟩

  | .ascribe e ty => do
    let ⟨e', he⟩ ← check Γ e ty.toCore
    return ⟨ty.toCore, e', he⟩

  | .someE e => do
    let ⟨t, e', he⟩ ← infer Γ e
    return ⟨.option t, .someE e', .someE he⟩

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

  | .bind _ _ _ => sorry

  | .cases _ _ => sorry

  | .nil | .listLit [] | .noneE =>
    .error "cannot infer a type for this expression; add an annotation"

/-- Check a tuple's components against the product's component types. -/
def checkTuple (Γ : Context) :
    List Input.Expr → (ts : List Ty) → Result { es' : List Expr // TupleOfTy Γ es' ts }
  | [], [] => .ok ⟨[], .nil⟩

  | e :: es, t :: ts => do
    let ⟨e', he⟩ ← check Γ e t
    let ⟨es', hes⟩ ← checkTuple Γ es ts
    return ⟨e' :: es', .cons he hes⟩

  | [], _ :: _ | _ :: _, [] => .error "tuple has the wrong number of components"

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

end MathQL
