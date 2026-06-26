import MathQL.Name
import MathQL.Result
import MathQL.Ty

namespace MathQL

/-- The typing info of a domain. -/
structure DomainTy where
  inputField : List (Label × Ty)
  outputField : List Label

/-- A context describing which domains are available, with their typing info. -/
abbrev DomainContext := List (DomainName × DomainTy)

def DomainContext.empty : DomainContext := []

def DomainContext.extend (D : DomainContext) (x : DomainName) (d : DomainTy) : DomainContext :=
  (x, d) :: D

inductive Context.Entry where
  | const : Ty → Entry
  | domain : DomainTy → Entry

/-- Contexts. -/
structure Context where
  domain : DomainContext
  var : List (Ident × Context.Entry)

def Context.lookupConst (Γ : Context) (x : Ident) : Option Ty := do
  let ent ← Γ.var.lookup x
  match ent with
  | .const t => return t
  | .domain _ => .none

private def Context.lookupVar (Γ : Context) (x : Ident) : Option DomainTy := do
  let ent ← Γ.var.lookup x
  match ent with
  | .const _ => .none
  | .domain d => return d

def Context.lookupInputField (Γ : Context) (x : Ident) (l : Label) : Option Ty := do
  let d ← Γ.lookupVar x
  d.inputField.lookup l

def Context.isOutputField (Γ : Context) (x : Ident) (l : Label) : Option Bool := do
  let d ← Γ.lookupVar x
  return (d.outputField.elem l)

def Context.empty (D : DomainContext) : Context where
  domain := D
  var := []

def Context.extend (Γ : Context) (x : Ident) (ent : Entry) : Context :=
  { domain := Γ.domain, var := (x, ent) :: Γ.var }

def Context.extendMany (Γ : Context) : List (Ident × DomainName) → Option Context
| [] => return Γ
| (x, n) :: xns => do
  let d ← Γ.domain.lookup n
  let Γ := Γ.extend x (.domain d)
  Γ.extendMany xns
