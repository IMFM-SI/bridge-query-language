import Std.Internal.Parsec
import Std.Internal.Parsec.String
import MathQL.Surface

/-! A parser for MathQL concrete syntax, built on `Std.Internal.Parsec`.
UTF-8 operators (`∈ ∧ ∨ ¬ ≠ ≤ ≥ ⇒`) and ASCII synonyms (`in && || ! != <= >= =>`)
are both accepted. -/

namespace MathQL.Parsing

open Std.Internal.Parsec Std.Internal.Parsec.String
open MathQL.Surface

abbrev P := Parser

private def opt (p : P α) : P (Option α) := (do return some (← p)) <|> pure none

private partial def sepBy1 (p : P α) (sep : P Unit) : P (List α) := do
  let x ← p
  let xs ← many (do sep; p)
  return x :: xs.toList

private def sepBy (p : P α) (sep : P Unit) : P (List α) :=
  (sepBy1 p sep) <|> pure []

private def isIdentStart (c : Char) : Bool := c.isAlpha || c == '_'
private def isIdentRest (c : Char) : Bool := c.isAlphanum || c == '_'

private def keywords : List String :=
  ["if", "then", "else", "match", "with", "let", "in", "some", "none", "true", "false"]

/-- Skip whitespace. -/
private def sp : P Unit := ws

/-- A literal token, skipping trailing whitespace. -/
private def tok (s : String) : P Unit := do skipString s; sp

/-- A raw identifier (not yet checked against keywords). -/
private def rawIdent : P String := do
  let c ← satisfy isIdentStart
  let cs ← manyChars (satisfy isIdentRest)
  return c.toString ++ cs

/-- An identifier that is not a keyword, skipping trailing whitespace. -/
private def ident : P String := attempt do
  let s ← rawIdent
  if keywords.contains s then fail s!"unexpected keyword '{s}'"
  sp
  return s

/-- A keyword, not immediately followed by an identifier character. -/
private def keyword (s : String) : P Unit := attempt do
  skipString s
  notFollowedBy (satisfy isIdentRest)
  sp

private def intLit : P Int := do
  let ds ← many1Chars digit
  sp
  match ds.toInt? with
  | some n => return n
  | none => fail "bad integer"

private def stringLit : P String := do
  skipChar '"'
  let s ← manyChars (satisfy (· != '"'))
  skipChar '"'
  sp
  return s

private def compareOp : P String :=
  (tok "≤" *> pure "le") <|> (tok "<=" *> pure "le") <|>
  (tok "≥" *> pure "ge") <|> (tok ">=" *> pure "ge") <|>
  (tok "≠" *> pure "ne") <|> (tok "!=" *> pure "ne") <|>
  (tok "==" *> pure "eq") <|> (tok "=" *> pure "eq") <|>
  (tok "<" *> pure "lt") <|> (tok ">" *> pure "gt")

mutual

private partial def ptype : P STy :=
  (keyword "Int" *> pure STy.int) <|>
  (keyword "Bool" *> pure STy.bool) <|>
  (keyword "String" *> pure STy.string) <|>
  (do keyword "Option"; return STy.option (← ptype)) <|>
  (do keyword "List"; return STy.list (← ptype)) <|>
  (do tok "("; let ts ← sepBy ptype (tok ","); tok ")";
      return match ts with | [t] => t | _ => STy.prod ts) <|>
  (do return STy.name (← ident))

private partial def pattern : P Pat := do
  let p ← patternAtom
  (do tok "::"; return Pat.cons p (← pattern)) <|> pure p

private partial def patternAtom : P Pat :=
  (keyword "_" *> pure Pat.wild) <|>
  (keyword "none" *> pure Pat.noneP) <|>
  (do keyword "some"; return Pat.someP (← patternAtom)) <|>
  (do tok "."; return Pat.enumCtor (← ident)) <|>
  (do tok "["; tok "]"; return Pat.nil) <|>
  (do tok "{"; let fs ← sepBy (do let l ← ident; tok ":="; return (l, ← pattern)) (tok ","); tok "}";
      return Pat.record fs) <|>
  (do tok "("; let ps ← sepBy pattern (tok ","); tok ")";
      return match ps with | [p] => p | _ => Pat.tuple ps) <|>
  (do return Pat.var (← ident))

private partial def expr : P Expr :=
  ifExpr <|> matchExpr <|> letExpr <|> consExpr

private partial def ifExpr : P Expr := do
  keyword "if"; let c ← expr
  keyword "then"; let t ← expr
  keyword "else"; let e ← expr
  return Expr.ite c t e

private partial def letExpr : P Expr := do
  keyword "let"; let p ← pattern
  tok ":="; let v ← expr
  keyword "in"; let b ← expr
  return Expr.let p v b

private partial def matchExpr : P Expr := do
  keyword "match"; let s ← expr; keyword "with"
  let alts ← many1 (do
    tok "|"; let p ← pattern; (tok "⇒" <|> tok "=>"); return (p, ← expr))
  return Expr.mat s alts.toList

private partial def consExpr : P Expr := do
  let e ← orExpr
  (do tok "::"; return Expr.cons e (← consExpr)) <|> pure e

private partial def orExpr : P Expr := do
  let mut e ← andExpr
  let rest ← many (do (tok "∨" <|> tok "||"); andExpr)
  for r in rest do e := Expr.binop "or" e r
  return e

private partial def andExpr : P Expr := do
  let mut e ← cmpExpr
  let rest ← many (do (tok "∧" <|> tok "&&"); cmpExpr)
  for r in rest do e := Expr.binop "and" e r
  return e

private partial def cmpExpr : P Expr := do
  let l ← addExpr
  (do let op ← compareOp; return Expr.binop op l (← addExpr)) <|> pure l

private partial def addExpr : P Expr := do
  let mut e ← mulExpr
  let rest ← many ((do tok "+"; return ("add", ← mulExpr)) <|> (do tok "-"; return ("sub", ← mulExpr)))
  for (op, r) in rest do e := Expr.binop op e r
  return e

private partial def mulExpr : P Expr := do
  let mut e ← unaryExpr
  let rest ← many (do tok "*"; unaryExpr)
  for r in rest do e := Expr.binop "mul" e r
  return e

private partial def unaryExpr : P Expr :=
  (do (tok "¬" <|> tok "!"); return Expr.unop "not" (← unaryExpr)) <|>
  (do tok "-"; return Expr.unop "neg" (← unaryExpr)) <|>
  postfixExpr

private partial def postfixExpr : P Expr := do
  let mut e ← atomExpr
  let rest ← many (do tok "."; (do return Sum.inr (← intLitNat)) <|> (do return Sum.inl (← ident)))
  for r in rest do
    e := match r with | Sum.inl f => Expr.field e f | Sum.inr i => Expr.proj e i
  return e

private partial def intLitNat : P Nat := do
  let ds ← many1Chars digit
  sp
  return ds.toNat!

private partial def atomExpr : P Expr :=
  (do return Expr.int (← intLit)) <|>
  (keyword "true" *> pure (Expr.bool true)) <|>
  (keyword "false" *> pure (Expr.bool false)) <|>
  (keyword "none" *> pure Expr.noneE) <|>
  (do keyword "some"; return Expr.someE (← atomExpr)) <|>
  (do return Expr.str (← stringLit)) <|>
  (do tok "."; return Expr.enumCtor (← ident)) <|>
  (do tok "["; let items ← sepBy expr (tok ","); tok "]"; return Expr.listLit items) <|>
  (do tok "{"; let fs ← sepBy (do let l ← ident; tok ":="; return (l, ← expr)) (tok ","); tok "}";
      return Expr.record fs) <|>
  parenExpr <|>
  (do return Expr.var (← ident))

private partial def parenExpr : P Expr := do
  tok "("
  let first ← expr
  let r ← (do tok ":"; return Sum.inl (← ptype)) <|>
          (do let more ← many (do tok ","; expr); return Sum.inr more.toList)
  tok ")"
  return match r with
    | Sum.inl ty => Expr.ascribe first ty
    | Sum.inr [] => first
    | Sum.inr more => Expr.tuple (first :: more)

end

private def query : P Query := do
  sp; tok "{"
  let result ← expr
  tok "|"
  let var ← ident
  (keyword "in" <|> tok "∈")
  let domain ← ident
  let condition ← opt (do tok ","; expr)
  tok "}"
  eof
  return { result, var, domain, condition }

/-- Parse a MathQL query string. -/
def parse (s : String) : Except String Query := query.run s

end MathQL.Parsing
