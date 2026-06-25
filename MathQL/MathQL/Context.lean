import MathQL.Name
import MathQL.Ty
import MathQL.Pattern

namespace MathQL

/-- Contexts. -/
structure Context where
  ty : List (Ident × DefinedTy)
  var : List (Ident × Ty)

def Context.lookupVar (Γ : Context) (x : Ident) : Option Ty :=
  Γ.var.lookup x

def Context.lookupRecord (Γ : Context) (n : Ident) : Option (List (Label × Ty)) :=
  match Γ.ty.lookup n with
  | .none => .none
  | .some (.enum _) => .none
  | .some (.record fields) => .some fields

def Context.lookupEnum (Γ : Context) (n : Ident) : Option (List Ident) :=
  match Γ.ty.lookup n with
  | .none => .none
  | .some (.record _) => .none
  | .some (.enum cs) => .some cs

def Context.findEnum (Γ : Context) (c : Ident) : Option Ident :=
  let rec search : List (Ident × DefinedTy) → Option Ident
    | [] => .none
    | (_, .record _) :: ds => search ds
    | (n, .enum cs) :: ds => if c ∈ cs then .some n else search ds
  search Γ.ty

def Context.findLabel (Γ : Context) (l : Label) : Option (Ident × Ty) :=
  let rec search : List (Ident × DefinedTy) → Option (Ident × Ty)
    | [] => .none
    | (_, .enum _) :: ds => search ds
    | (n, .record fields) :: ds =>
      match fields.lookup l with
      | .none => search ds
      | .some t => .some (n, t)
  search Γ.ty

def Context.empty (tyDefs : List (Ident × DefinedTy)) : Context where
  ty := tyDefs
  var := []

def Context.extend (Γ : Context) (x : Ident) (t : Ty) : Context where
  ty := Γ.ty
  var := (x, t) :: Γ.var

mutual

def Context.extendPattern (Γ : Context) (p : Pattern) (t : Ty) : Option Context :=
  match p, t with
  | .wild, _ => return Γ
  | .var x, t => return (Γ.extend x t)
  | .tuple ps, .prod ts => Γ.extendTuplePattern ps ts
  | _, _ => .none

def Context.extendTuplePattern (Γ : Context) (ps : List Pattern) (ts : List Ty) : Option Context :=
  match ps, ts with
  | [], [] => pure Γ
  | p :: ps, t :: ts => do
    let Δ ← Γ.extendPattern p t
    Δ.extendTuplePattern ps ts
  | [], _::_ | _::_, [] => .none

end
