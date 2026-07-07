import Std.Internal.Parsec
import Std.Internal.Parsec.String
import MathQL.Input

/-! A parser for MathQL concrete syntax, built on `Std.Internal.Parsec`.
UTF-8 operators (`∈ ∧ ∨ ¬ ≠ ≤ ≥`) and ASCII synonyms (`in && || ! != <= >=`)
are both accepted. -/

namespace MathQL.Parsing

open Std.Internal.Parsec Std.Internal.Parsec.String
open MathQL

private partial def sepBy1 {α} (p : Parser α) (sep : Parser Unit) : Parser (List α) := do
  let x ← p
  let xs ← many (do sep; p)
  return x :: xs.toList

private def sepBy {α} (p : Parser α) (sep : Parser Unit) : Parser (List α) :=
  (sepBy1 p sep) <|> pure []

private partial def chainl1Core {α} (p : Parser α) (op : Parser (α → α → α)) (l : α) : Parser α :=
  (do let f ← op; chainl1Core p op (f l (← p))) <|> pure l

/-- One or more `p`, combined left-associatively by `op`. -/
private def chainl1 {α} (p : Parser α) (op : Parser (α → α → α)) : Parser α := do
  chainl1Core p op (← p)

private def isIdentStart (c : Char) : Bool := c.isAlpha || c == '_'
private def isIdentRest (c : Char) : Bool := c.isAlphanum || c == '_'

private def keywords : List String :=
  ["if", "then", "else", "in", "true", "false", "defined", "undefined"]

/-- A literal token, skipping trailing whitespace. -/
private def tok (s : String) : Parser Unit := do skipString s; ws

/-- A raw identifier (not yet checked against keywords). -/
private def rawIdent : Parser String := do
  let c ← satisfy isIdentStart
  let cs ← manyChars (satisfy isIdentRest)
  return c.toString ++ cs

/-- An identifier that is not a keyword, skipping trailing whitespace. -/
private def ident : Parser String := attempt do
  let s ← rawIdent
  if keywords.contains s then fail s!"unexpected keyword '{s}'"
  ws
  return s

/-- A keyword, not immediately followed by an identifier character. -/
private def keyword (s : String) : Parser Unit := attempt do
  skipString s
  notFollowedBy (satisfy isIdentRest)
  ws

private def intLit : Parser Int := do
  let n ← digits
  ws
  return (Int.ofNat n)

private def stringLit : Parser String := do
  skipChar '"'
  let s ← manyChars (satisfy (· != '"'))
  skipChar '"'
  ws
  return s

private def compareOp : Parser ComparisonOp :=
  (tok "≤" *> pure .le) <|> (tok "<=" *> pure .le) <|>
  (tok "≥" *> pure .ge) <|> (tok ">=" *> pure .ge) <|>
  (tok "≠" *> pure .ne) <|> (tok "!=" *> pure .ne) <|>
  (tok "==" *> pure .eq) <|> (tok "=" *> pure .eq) <|>
  (tok "<" *> pure .lt) <|> (tok ">" *> pure .gt)

mutual

private partial def expr : Parser Input.Expr :=
  ifExpr <|> orExpr

private partial def ifExpr : Parser Input.Expr := do
  keyword "if"; let c ← expr
  keyword "then"; let t ← expr
  keyword "else"; let e ← expr
  return .ite c t e

private partial def orExpr : Parser Input.Expr :=
  chainl1 andExpr ((tok "∨" <|> tok "||") *> pure (.binop .or))

private partial def andExpr : Parser Input.Expr :=
  chainl1 cmpExpr ((tok "∧" <|> tok "&&") *> pure (.binop .and))

private partial def cmpExpr : Parser Input.Expr := do
  let l ← addExpr
  (do let op ← compareOp; return .compare op l (← addExpr)) <|> pure l

private partial def addExpr : Parser Input.Expr :=
  chainl1 mulExpr
    ((tok "+" *> pure (.binop .add)) <|> (tok "-" *> pure (.binop .sub)))

private partial def mulExpr : Parser Input.Expr :=
  chainl1 unaryExpr (tok "*" *> pure (.binop .mul))

private partial def unaryExpr : Parser Input.Expr :=
  (do keyword "id"; tok "("; let e ← expr; tok ")"; return .id e) <|>
  (do keyword "defined"; return .defined (← unaryExpr)) <|>
  (do keyword "undefined"; return .undefined (← unaryExpr)) <|>
  (do (tok "¬" <|> tok "!"); return .unop UnaryOp.not (← unaryExpr)) <|>
  (do tok "-"; return .unop UnaryOp.neg (← unaryExpr)) <|>
  postfixExpr

private partial def postfixExpr : Parser Input.Expr := do
  postfixProj (← atomExpr)

/-- Apply any number of postfix projections: tuple projections `.i` (with `i` a
    numeral) and field projections `.label`, off an arbitrary expression. -/
private partial def postfixProj (e : Input.Expr) : Parser Input.Expr :=
  (do let i ← attempt (do tok "."; intLitNat); postfixProj (.proj e i)) <|>
  (do let l ← attempt (do tok "."; ident); postfixProj (.field e l)) <|>
  pure e

private partial def intLitNat : Parser Nat := do
  let n ← digits
  ws
  return n

private partial def atomExpr : Parser Input.Expr :=
  (do return .int (← intLit)) <|>
  (keyword "true" *> pure (.bool true)) <|>
  (keyword "false" *> pure (.bool false)) <|>
  (do return .str (← stringLit)) <|>
  (do tok "["; let items ← sepBy expr (tok ","); tok "]"; return .list items) <|>
  parenExpr <|>
  identExpr

/-- A bare identifier: a domain variable or a named constant, resolved during
    elaboration; `D[e]` is the object of domain `D` whose primary key is `e`.
    Field projection is handled by `postfixProj`. -/
private partial def identExpr : Parser Input.Expr := do
  let x ← ident
  (do tok "["; let e ← expr; tok "]"; return .obj x e) <|>
  pure (.ident x)

private partial def parenExpr : Parser Input.Expr := do
  tok "("
  let first ← expr
  let more ← many (do tok ","; expr)
  tok ")"
  return match more.toList with
    | [] => first
    | rest => .tuple (first :: rest)

end

/-- One output item: `id(x)` (the primary key), a field projection `x.label`,
    or a bare `x` (the whole object). -/
private def outputItem : Parser Input.OutputItem :=
  (do keyword "id"; tok "("; let x ← ident; tok ")"; return .id x) <|>
  (do
    let x ← ident
    (do let l ← attempt (do tok "."; ident); return Input.OutputItem.field x l) <|>
    pure (Input.OutputItem.ident x))

/-- Run a parser over an entire string, requiring it to consume all input. -/
private def runComplete {α} (p : Parser α) (s : String) : Except String α :=
  (do ws; let r ← p; eof; return r).run s

/-- Parse an expression from a string. Used by the JSON query decoder. -/
def parseExpr : String → Except String Input.Expr := runComplete expr

/-- Parse an output item (`x`, `x.label`, or `id(x)`) from a string. -/
def parseOutputItem : String → Except String Input.OutputItem := runComplete outputItem

/-- Parse a single identifier from a string. -/
def parseIdent : String → Except String String := runComplete ident

end MathQL.Parsing
