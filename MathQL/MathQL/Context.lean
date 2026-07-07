import MathQL.Name
import MathQL.Result
import MathQL.Ty

namespace MathQL

/-- The typing info of a domain. -/
structure DomainTy where
  /-- The type of id for this domain -/
  idTy : Ty
  /-- Available field projections with their types -/
  inputField : List (Label × Ty)
  /-- Available field projections in the output -/
  outputField : List Label

/-- A context describing which domains are available, with their typing info. -/
abbrev DomainContext := List (DomainName × DomainTy)

/-- Contexts. -/
structure Context where
  domain : DomainContext
  ident : List (Ident × Ty)

def Context.lookupIdent (Γ : Context) (x : Ident) : Option Ty := Γ.ident.lookup x

def Context.lookupDomain (Γ : Context) (d : DomainName) : Option DomainTy := Γ.domain.lookup d

def Context.lookupInputField (Γ : Context) (x : Ident) (l : Label) : Option Ty := do
  let t ← Γ.lookupIdent x
  match t with
  | .domain d =>
    let td ← Γ.lookupDomain d
    td.inputField.lookup l
  | _ => none

def Context.isOutputField (Γ : Context) (x : Ident) (l : Label) : Option Bool := do
  let t ← Γ.lookupIdent x
  match t with
  | .domain d =>
    let td ← Γ.lookupDomain d
    td.outputField.elem l
  | _ => none

def Context.empty (D : DomainContext) : Context where
  domain := D
  ident := []

def Context.extendIdent (Γ : Context) (x : Ident) (t : Ty) : Context :=
  { domain := Γ.domain, ident := (x, t) :: Γ.ident }
