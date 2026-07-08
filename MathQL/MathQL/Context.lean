import MathQL.Name
import MathQL.Result
import MathQL.Ty

namespace MathQL

inductive DomainOrTy where
  | domain : DomainName → DomainOrTy
  | ty : Ty → DomainOrTy

/-- The typing info of a domain. -/
structure DomainTy where
  /-- The type of id for this domain -/
  idTy : Ty
  /-- Available field projections with their types -/
  inputField : List (Label × DomainOrTy)
  /-- Available field projections in the output -/
  outputField : List Label

/-- A context describing which domains are available, with their typing info. -/
abbrev DomainContext := List (DomainName × DomainTy)

/-- Contexts. -/
structure Context where
  domain : DomainContext
  ident : List (Ident × DomainOrTy)

def Context.lookupIdent (Γ : Context) (x : Ident) : Option Ty := do
  let ent ← Γ.ident.lookup x
  match ent with
  | .ty t => pure t
  | .domain _ => .none

def Context.lookupDomainIdent (Γ : Context) (x : Ident) : Option DomainName := do
  let ent ← Γ.ident.lookup x
  match ent with
  | .ty _ => .none
  | .domain d => pure d

def Context.lookupDomain (Γ : Context) (d : DomainName) : Option DomainTy := Γ.domain.lookup d

def Context.lookupInputField (Γ : Context) (d : DomainName) (l : Label) : Option DomainOrTy := do
  let td ← Γ.lookupDomain d
  td.inputField.lookup l

def Context.isOutputField (Γ : Context) (d : DomainName) (l : Label) : Option Bool := do
  let td ← Γ.lookupDomain d
  td.outputField.elem l

def Context.empty (D : DomainContext) : Context where
  domain := D
  ident := []

def Context.extendIdent (Γ : Context) (x : Ident) (t : Ty) : Context :=
  { domain := Γ.domain, ident := (x, .ty t) :: Γ.ident }

def Context.extendDomainIdent (Γ : Context) (x : Ident) (d : DomainName) : Context :=
  { domain := Γ.domain, ident := (x, .domain d) :: Γ.ident }
