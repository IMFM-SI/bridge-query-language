import MathQL.Expr
import MathQL.Result
import Lean.Data.Json

/-! The Lean interpreter for the `postprocess` clause, shared by every backend. It runs on
decoded result rows, after SQL, and evaluates the entries in order: each entry sees the output
columns and the entries before it, and an entry whose evaluation fails becomes `null`.
Extracted unchanged from the former `Execute` module. -/

namespace MathQL

/-- A runtime environment for postprocessing expressions -/
structure PostEnvironment where
  ident : List (Ident × Lean.Json)
  function : List (Ident × (List Lean.Json → Result Lean.Json))

def evalUnaryOp : UnaryOp → Lean.Json → Result Lean.Json
| .not, j => do
  let b ← j.getBool?
  return .bool (not b)
| .neg, j => do
  let k ← j.getInt?
  return .num (- k)

def evalBinaryOp : BinaryOp → Lean.Json → Lean.Json → Result Lean.Json
| .and, v1, v2 => do
  let b1 ← v1.getBool?
  let b2 ← v2.getBool?
  return .bool (b1 && b2)
| .or, v1, v2 => do
  let b1 ← v1.getBool?
  let b2 ← v2.getBool?
  return .bool (b1 || b2)
| .add, v1, v2 => do
  let k1 ← v1.getInt?
  let k2 ← v2.getInt?
  return .num (k1 + k2)
| .sub, v1, v2 => do
  let k1 ← v1.getInt?
  let k2 ← v2.getInt?
  return .num (k1 - k2)
| .mul, v1, v2 => do
  let k1 ← v1.getInt?
  let k2 ← v2.getInt?
  return .num (k1 * k2)
| .div, v1, v2 => do
  let k1 ← v1.getInt?
  let k2 ← v2.getInt?
  if k2 == 0 then throw "division by zero" else return .num (k1.tdiv k2)

/-- Compare two JSON values at their MathQL type. -/
def compareJson : Ty → Lean.Json → Lean.Json → Result Ordering
| .int, j1, j2 => do
  let k1 ← j1.getInt?
  let k2 ← j2.getInt?
  return compare k1 k2
| .bool, j1, j2 => do
  let b1 ← j1.getBool?
  let b2 ← j2.getBool?
  return compare b1 b2
| .string, j1, j2 => do
  let s1 ← j1.getStr?
  let s2 ← j2.getStr?
  return compare s1 s2
| .list _, j1, j2
| .prod _, j1, j2 => return compare j1.compress j2.compress

def evalComparison (op : ComparisonOp) (t : Ty) (j1 : Lean.Json) (j2 : Lean.Json) :
    Result Lean.Json :=
  match j1, j2 with
  | .null, _ | _, .null => return .null
  | _, _ => do
    let c ← compareJson t j1 j2
    return .bool <|
      match op with
      | .eq => c.isEq
      | .ne => c.isNe
      | .lt => c.isLT
      | .le => c.isLE
      | .gt => c.isGT
      | .ge => c.isGE

/-- Whether a result is a non-null value; a failure counts as null. -/
def isDefined : Result Lean.Json → Bool
| .ok .null | .error _ => false
| .ok _ => true

def evalPostExpr (env : PostEnvironment) : Expr → Result Lean.Json

| .int n => return .num n

| .bool b => return .bool b

| .str s => return .str s

| .ident x =>
  match env.ident.lookup x with
  | none => throw s!"unknown identifier {x.name}"
  | some v => return v

| .id _ =>
  throw s!"id is not allowed in postprocessing"

| .field _ _ =>
  throw s!"field projection is not allowed in postprocessing"

| .call f args =>
  match env.function.lookup f with
  | .none => throw s!"unknown function {f.name}"
  | .some f => do
    let vs ← args.mapM (evalPostExpr env)
    f vs

| .unop op e => do
  let v ← evalPostExpr env e
  evalUnaryOp op v

| .binop op e1 e2 => do
  let v1 ← evalPostExpr env e1
  let v2 ← evalPostExpr env e2
  evalBinaryOp op v1 v2

| .compare op t e1 e2 => do
  let v1 ← evalPostExpr env e1
  let v2 ← evalPostExpr env e2
  evalComparison op t v1 v2

| .list es => do
  let vs ← es.mapM (evalPostExpr env)
  return .arr vs.toArray

| .tuple es => do
  let vs ← es.mapM (evalPostExpr env)
  return .arr vs.toArray

| .proj e1 n => do
  let v ← evalPostExpr env e1
  v.getArrVal? n -- We're relying here on Result = Except String

| .ite b e1 e2 => do
  let b ← evalPostExpr env b
  match b.getBool? with
  | .ok true => evalPostExpr env e1
  | .ok false => evalPostExpr env e2
  | .error msg => throw s!"boolean expected ({msg})"

| .defined e =>
  return .bool (isDefined (evalPostExpr env e))

| .undefined e =>
  return .bool (not (isDefined (evalPostExpr env e)))


def evalPostprocess (env : PostEnvironment) :
  List (Ident × Ty × Expr) → List (Ident × Lean.Json)
| [] => []
| (x, _, e) :: ps =>
  let v := match evalPostExpr env e with | .ok v => v | .error _ => .null
  let vs := evalPostprocess {env with ident := (x, v) :: env.ident} ps
  (x, v) :: vs

end MathQL
