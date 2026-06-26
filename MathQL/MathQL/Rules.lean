import MathQL.Ty
import MathQL.Context
import MathQL.Expr

namespace MathQL

mutual

inductive ExprOfTy : Context → Expr → Ty → Prop where

  | const : ∀ {Γ : Context} {x t},
        Γ.lookupConst x = .some t →
        ExprOfTy Γ (.const x) t

  | int : ∀ {Γ n},
        ExprOfTy Γ (.int n) .int

  | bool : ∀ {Γ b},
        ExprOfTy Γ (.bool b) .bool

  | str : ∀ {Γ s},
        ExprOfTy Γ (.str s) .string

  | field : ∀ {Γ n l t},
        Γ.lookupInputField n l = .some t →
        ExprOfTy Γ (.field n l) t

  | unop : ∀ {Γ op e t₁ t₂},
        unaryTy op = (t₁, t₂) →
        ExprOfTy Γ e t₁ →
        ExprOfTy Γ (.unop op e) t₂

  | binop : ∀ {Γ op e₁ e₂ t₁ t₂ t₃}, binaryTy op = (t₁, t₂, t₃) →
        ExprOfTy Γ e₁ t₁ →
        ExprOfTy Γ e₂ t₂ →
        ExprOfTy Γ (.binop op e₁ e₂) t₃

  | tuple : ∀ {Γ es ts},
        TupleOfTy Γ es ts →
        ExprOfTy Γ (.tuple es) (.prod ts)

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

  | ite : ∀ {Γ c a b t},
        ExprOfTy Γ c .bool →
        ExprOfTy Γ a t →
        ExprOfTy Γ b t →
        ExprOfTy Γ (.ite c a b) t

  | defined : ∀ {Γ e t},
        ExprOfTy Γ e t →
        ExprOfTy Γ (.defined e) .bool

  | undefined : ∀ {Γ e t},
        ExprOfTy Γ e t →
        ExprOfTy Γ (.undefined e) .bool

inductive TupleOfTy : Context → List Expr → List Ty → Prop where
  | nil : ∀ {Γ}, TupleOfTy Γ [] []
  | cons : ∀ {Γ e t es ts}, ExprOfTy Γ e t → TupleOfTy Γ es ts → TupleOfTy Γ (e :: es) (t :: ts)

end
