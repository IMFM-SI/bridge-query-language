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
  ifExpr <|> consExpr

private partial def ifExpr : Parser Input.Expr := do
  keyword "if"; let c ← expr
  keyword "then"; let t ← expr
  keyword "else"; let e ← expr
  return .ite c t e

private partial def consExpr : Parser Input.Expr := do
  let e ← orExpr
  (do tok "::"; return .cons e (← consExpr)) <|> pure e

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
  (do keyword "defined"; return .defined (← unaryExpr)) <|>
  (do keyword "undefined"; return .undefined (← unaryExpr)) <|>
  (do (tok "¬" <|> tok "!"); return .unop UnaryOp.not (← unaryExpr)) <|>
  (do tok "-"; return .unop UnaryOp.neg (← unaryExpr)) <|>
  postfixExpr

private partial def postfixExpr : Parser Input.Expr := do
  postfixProj (← atomExpr)

/-- Apply any number of tuple projections `.i` (with `i` a numeral). Field
    access `x.label` is handled at the atom, since a field projects a domain
    variable, not an arbitrary expression. -/
private partial def postfixProj (e : Input.Expr) : Parser Input.Expr :=
  (do let i ← attempt (do tok "."; intLitNat); postfixProj (.proj e i)) <|> pure e

private partial def intLitNat : Parser Nat := do
  let n ← digits
  ws
  return n

private partial def atomExpr : Parser Input.Expr :=
  (do return .int (← intLit)) <|>
  (keyword "true" *> pure (.bool true)) <|>
  (keyword "false" *> pure (.bool false)) <|>
  (do return .str (← stringLit)) <|>
  (do tok "["; let items ← sepBy expr (tok ","); tok "]"; return .listLit items) <|>
  parenExpr <|>
  identExpr

/-- A bare identifier is a constant; `x.label` is a field projection off the
    domain variable `x`. -/
private partial def identExpr : Parser Input.Expr := do
  let x ← ident
  (do let l ← attempt (do tok "."; ident); return Input.Expr.field x l) <|>
  pure (Input.Expr.const x)

private partial def parenExpr : Parser Input.Expr := do
  tok "("
  let first ← expr
  let more ← many (do tok ","; expr)
  tok ")"
  return match more.toList with
    | [] => first
    | rest => .tuple (first :: rest)

end

/-- One output item: a domain variable `x` (the whole object) or a field
    projection `x.label`. -/
private def outputItem : Parser (String × Option String) := do
  let x ← ident
  (do let l ← attempt (do tok "."; ident); return (x, some l)) <|> pure (x, none)

/-- One domain binding, `x ∈ D`. -/
private def binding : Parser (String × String) := do
  let x ← ident
  (keyword "in" <|> tok "∈")
  let d ← ident
  return (x, d)

private def query : Parser Input.Query := do
  ws; tok "{"
  let output ← sepBy1 outputItem (tok ",")
  tok "|"
  let first ← binding
  let more ← many (attempt (do tok ","; binding))
  let condition ← (do tok ","; expr) <|> pure (Input.Expr.bool true)
  tok "}"
  eof
  return { output, vars := first :: more.toList, condition }

/-- Parse a MathQL query string. -/
def parse (s : String) : Except String Input.Query := query.run s

end MathQL.Parsing
