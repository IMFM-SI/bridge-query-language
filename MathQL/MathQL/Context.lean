import MathQL.Name
import MathQL.Result
import MathQL.Ty

namespace MathQL

abbrev TyDefs := List (Ident × TyDef)

/-- Contexts. -/
structure Context where
  tyDefs : TyDefs
  var : List (Ident × Ty)

def Context.lookupVar (Γ : Context) (x : Ident) : Option Ty :=
  Γ.var.lookup x

def Context.lookupRecord (Γ : Context) (n : Ident) : Option (List (Label × Ty)) :=
  match Γ.tyDefs.lookup n with
  | .none => .none
  | .some (.enum _) => .none
  | .some (.record fields) => .some fields

def Context.lookupEnum (Γ : Context) (n : Ident) : Option (List Ident) :=
  match Γ.tyDefs.lookup n with
  | .none => .none
  | .some (.record _) => .none
  | .some (.enum cs) => .some cs

def Context.findEnum (Γ : Context) (c : Ident) : Option Ident :=
  let rec search : TyDefs → Option Ident
    | [] => .none
    | (_, .record _) :: ds => search ds
    | (n, .enum cs) :: ds => if c ∈ cs then .some n else search ds
  search Γ.tyDefs

def Context.findLabel (Γ : Context) (l : Label) : Option (Ident × Ty) :=
  let rec search : TyDefs → Option (Ident × Ty)
    | [] => .none
    | (_, .enum _) :: ds => search ds
    | (n, .record fields) :: ds =>
      match fields.lookup l with
      | .none => search ds
      | .some t => .some (n, t)
  search Γ.tyDefs

def Context.empty (tyDefs : TyDefs) : Context where
  tyDefs := tyDefs
  var := []

def Context.extend (Γ : Context) (x : Ident) (t : Ty) : Context where
  tyDefs := Γ.tyDefs
  var := (x, t) :: Γ.var
