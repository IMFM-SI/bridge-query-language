import MathQL.Name
import MathQL.Result
import MathQL.Ty

namespace MathQL

structure InputField where
  /-- The type in MathQL -/
  ty : Ty
  /-- Is it part of the primary key? -/
  isPrimary : Bool

/-- The typing info of a domain. -/
structure DomainTy where
  /-- Field projections in the query -/
  inputField : List (Label × InputField)
  /-- Fields pointing to other domains -/
  domainField : List (Label × DomainName)

abbrev DomainContext := List (DomainName × DomainTy)

inductive Entry where
  | ty : Ty → Entry
  | domain : DomainName → Entry

/-- Contexts. -/
structure Context where
  domain : DomainContext
  ident : List (Ident × Entry)

def Context.getIdent (Γ : Context) (x : Ident) : Result Ty :=
  match Γ.ident.lookup x with
  | .some (.ty t) => return t
  | .some (.domain _) => throw s!"{x} is a domain but a constant was expected"
  | .none => throw s!"unknown identifier {x}"

def Context.getDomainIdent (Γ : Context) (x : Ident) : Result DomainName :=
  match Γ.ident.lookup x with
  | .some (.domain d) => return d
  | .some (.ty _) => throw s!"{x} is a constant but a domain was expected"
  | .none => throw s!"unknown domain name {x}"

def Context.getDomain (Γ : Context) (d : DomainName) : Result DomainTy :=
  match Γ.domain.lookup d with
  | .some dt => return dt
  | .none => throw s!"unknown domain {d}"

def Context.getPrimaryKey (Γ : Context) (d : DomainName) : Result (List (Label × Ty)) := do
  let dt ← Γ.getDomain d
  return (dt.inputField.filter (fun (_, f)=> f.isPrimary)).map (fun (l, f) => (l, f.ty))

def Context.getIdTys (Γ : Context) (d : DomainName) : Result (List Ty) := do
  let ts ← Γ.getPrimaryKey d
  return (ts.map Prod.snd)

def Context.getInputField (Γ : Context) (d : DomainName) (l : Label) : Result InputField := do
  let td ← Γ.getDomain d
  match td.inputField.lookup l with
  | .some f => return f
  | .none => throw s!"domain {d} does not have a field {l}"

def Context.getDomainField (Γ : Context) (d : DomainName) (l : Label) : Result DomainName := do
  let td ← Γ.getDomain d
  match td.domainField.lookup l with
  | .some dn => return dn
  | .none => throw s!"domain {d} does not have a field {l}"

def Context.getInputFieldTy (Γ : Context) (d : DomainName) (l : Label) : Result Ty := do
  let ft ← Γ.getInputField d l
  return ft.ty

def Context.empty (D : DomainContext) : Context where
  domain := D
  ident := []

def Context.extendIdent (Γ : Context) (x : Ident) (t : Ty) : Context :=
  { domain := Γ.domain, ident := (x, .ty t) :: Γ.ident }

def Context.extendDomainIdent (Γ : Context) (x : Ident) (d : DomainName) : Context :=
  { domain := Γ.domain, ident := (x, .domain d) :: Γ.ident }
