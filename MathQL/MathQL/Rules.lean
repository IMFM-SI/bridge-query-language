import MathQL.Ty
import MathQL.Context
import MathQL.Expr

namespace MathQL

mutual

inductive ExprOfTy : Context → Expr → Ty → Prop where
  | var : ∀ {Γ : Context} {x t},
        Γ.lookupVar x = .some t →
        ExprOfTy Γ (.var x) t
  | int : ∀ {Γ n},
        ExprOfTy Γ (.int n) .int
  | bool : ∀ {Γ b},
        ExprOfTy Γ (.bool b) .bool
  | str : ∀ {Γ s},
        ExprOfTy Γ (.str s) .string
  | enum : ∀ {Γ n c},
        Γ.findEnum c = .some n →
        ExprOfTy Γ (.enum c) (.name n)
  | field : ∀ {Γ e n l t},
        Γ.findLabel l = .some (n, t) →
        ExprOfTy Γ e (.name n) →
        ExprOfTy Γ (.field e l) t
  | unop : ∀ {Γ op e t₁ t₂},
        unaryTy op = (t₁, t₂) →
        ExprOfTy Γ e t₁ →
        ExprOfTy Γ (.unop op e) t₂
  | binop : ∀ {Γ op e₁ e₂ t₁ t₂ t₃}, binaryTy op = (t₁, t₂, t₃) →
        ExprOfTy Γ e₁ t₁ →
        ExprOfTy Γ e₂ t₂ →
        ExprOfTy Γ (.binop op e₁ e₂) t₃
  | tuple : ∀ {Γ es ts}, TupleOfTy Γ es ts → ExprOfTy Γ (.tuple es) (.prod ts)
  | proj : ∀ {Γ e ts i t},
        ExprOfTy Γ e (.prod ts) →
        ts[i]? = .some t →
        ExprOfTy Γ (.proj e i) t
  | nil : ∀ {Γ t},
        ExprOfTy Γ .nil (.list t)
  | cons : ∀ {Γ e es t},
        ExprOfTy Γ e t →
        ExprOfTy Γ es (.list t) →
        ExprOfTy Γ (.cons e es) (.list t)
  | someE : ∀ {Γ e t},
        ExprOfTy Γ e t →
        ExprOfTy Γ (.someE e) (.option t)
  | noneE : ∀ {Γ t},
        ExprOfTy Γ .noneE (.option t)
  | ite : ∀ {Γ c a b t},
        ExprOfTy Γ c .bool →
        ExprOfTy Γ a t →
        ExprOfTy Γ b t →
        ExprOfTy Γ (.ite c a b) t
  | bind : ∀ {Γ Δ p t₁ t₂ e₁ e₂},
        ExprOfTy Γ e₁ t₁ →
        Γ.extendPattern p t₁ = .some Δ →
        ExprOfTy Δ e₂ t₂ →
        ExprOfTy Γ (.bind p e₁ e₂) t₂

inductive TupleOfTy : Context → List Expr → List Ty → Prop where
  | nil : ∀ {Γ}, TupleOfTy Γ [] []
  | cons : ∀ {Γ e t es ts}, ExprOfTy Γ e t → TupleOfTy Γ es ts → TupleOfTy Γ (e :: es) (t :: ts)

end

/-- A comprehension `{ result | var ∈ domain, condition }`. -/
structure Query (tyDefs : List (Ident × DefinedTy)) where
  result : Expr
  resultTy : Ty
  var : Ident
  domain : Ty
  resultOfTy : ExprOfTy ((Context.empty tyDefs).extend var domain) result resultTy
  condition : Expr
  conditionOfBool : ExprOfTy ((Context.empty tyDefs).extend var domain) condition .bool
deriving Repr
