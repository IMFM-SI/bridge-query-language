import Std.Internal.Parsec
import Std.Internal.Parsec.String
import MathQL.Input

/-! A parser for MathQL concrete syntax, built on `Std.Internal.Parsec`.
UTF-8 operators (`∈ ∧ ∨ ¬ ≠ ≤ ≥ ⇒`) and ASCII synonyms (`in && || ! != <= >= =>`)
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
  ["if", "then", "else", "match", "with", "let", "in", "some", "none", "true", "false"]

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

private def compareOp : Parser BinaryOp :=
  (tok "≤" *> pure .le) <|> (tok "<=" *> pure .le) <|>
  (tok "≥" *> pure .ge) <|> (tok ">=" *> pure .ge) <|>
  (tok "≠" *> pure .ne) <|> (tok "!=" *> pure .ne) <|>
  (tok "==" *> pure .eq) <|> (tok "=" *> pure .eq) <|>
  (tok "<" *> pure .lt) <|> (tok ">" *> pure .gt)

mutual

private partial def ptype : Parser Input.Ty :=
  (keyword "Int" *> pure .int) <|>
  (keyword "Bool" *> pure .bool) <|>
  (keyword "String" *> pure .string) <|>
  (do keyword "Option"; return .option (← ptype)) <|>
  (do keyword "List"; return .list (← ptype)) <|>
  (do tok "("; let ts ← sepBy ptype (tok ","); tok ")";
      return match ts with | [t] => t | _ => .prod ts) <|>
  (do return .name (← ident))

private partial def pattern : Parser Input.Pattern := do
  let p ← patternAtom
  (do tok "::"; return .cons p (← pattern)) <|> pure p

private partial def patternAtom : Parser Input.Pattern :=
  (keyword "_" *> pure .wild) <|>
  (keyword "none" *> pure .noneP) <|>
  (do keyword "some"; return .someP (← patternAtom)) <|>
  (do tok "."; return .enumCtor (← ident)) <|>
  (do tok "["; tok "]"; return .nil) <|>
  (do tok "("; let ps ← sepBy pattern (tok ","); tok ")";
      return match ps with | [p] => p | _ => .tuple ps) <|>
  (do return .var (← ident))

private partial def expr : Parser Input.Expr :=
  ifExpr <|> matchExpr <|> letExpr <|> consExpr

private partial def ifExpr : Parser Input.Expr := do
  keyword "if"; let c ← expr
  keyword "then"; let t ← expr
  keyword "else"; let e ← expr
  return .ite c t e

private partial def letExpr : Parser Input.Expr := do
  keyword "let"; let p ← pattern
  tok ":="; let v ← expr
  keyword "in"; let b ← expr
  return .bind p v b

private partial def matchExpr : Parser Input.Expr := do
  keyword "match"; let s ← expr; keyword "with"
  let alts ← many1 (do
    tok "|"; let Parser ← pattern; (tok "⇒" <|> tok "=>"); return (Parser, ← expr))
  return .cases s alts.toList

private partial def consExpr : Parser Input.Expr := do
  let e ← orExpr
  (do tok "::"; return .cons e (← consExpr)) <|> pure e

private partial def orExpr : Parser Input.Expr :=
  chainl1 andExpr ((tok "∨" <|> tok "||") *> pure (.binop .or))

private partial def andExpr : Parser Input.Expr :=
  chainl1 cmpExpr ((tok "∧" <|> tok "&&") *> pure (.binop .and))

private partial def cmpExpr : Parser Input.Expr := do
  let l ← addExpr
  (do let op ← compareOp; return .binop op l (← addExpr)) <|> pure l

private partial def addExpr : Parser Input.Expr :=
  chainl1 mulExpr
    ((tok "+" *> pure (.binop .add)) <|> (tok "-" *> pure (.binop .sub)))

private partial def mulExpr : Parser Input.Expr :=
  chainl1 unaryExpr (tok "*" *> pure (.binop .mul))

private partial def unaryExpr : Parser Input.Expr :=
  (do (tok "¬" <|> tok "!"); return .unop UnaryOp.not (← unaryExpr)) <|>
  (do tok "-"; return .unop UnaryOp.neg (← unaryExpr)) <|>
  postfixExpr

private partial def postfixExpr : Parser Input.Expr := do
  postfixCore (← atomExpr)

private partial def postfixCore (e : Input.Expr) : Parser Input.Expr :=
  (do tok "."
      let step ← (do return .proj e (← intLitNat)) <|> (do return .field e (← ident))
      postfixCore step) <|>
  pure e

private partial def intLitNat : Parser Nat := do
  let n ← digits
  ws
  return n

private partial def atomExpr : Parser Input.Expr :=
  (do return .int (← intLit)) <|>
  (keyword "true" *> pure (.bool true)) <|>
  (keyword "false" *> pure (.bool false)) <|>
  (keyword "none" *> pure .noneE) <|>
  (do keyword "some"; return .someE (← atomExpr)) <|>
  (do return .str (← stringLit)) <|>
  (do tok "."; return .enumCtor (← ident)) <|>
  (do tok "["; let items ← sepBy expr (tok ","); tok "]"; return .listLit items) <|>
  (do return .var (← ident))

private partial def parenExpr : Parser Input.Expr := do
  tok "("
  let first ← expr
  let r ← (do tok ":"; return Sum.inl (← ptype)) <|>
          (do let more ← many (do tok ","; expr); return Sum.inr more.toList)
  tok ")"
  return match r with
    | Sum.inl ty => .ascribe first ty
    | Sum.inr [] => first
    | Sum.inr more => .tuple (first :: more)

end

private def query : Parser Input.Query := do
  ws; tok "{"
  let result ← expr
  tok "|"
  let var ← ident
  (keyword "in" <|> tok "∈")
  let domain ← ident
  let condition ← optional (do tok ","; expr)
  tok "}"
  eof
  return { result, var, domain, condition }

/-- Parse a MathQL query string. -/
def parse (s : String) : Except String Input.Query := query.run s

end MathQL.Parsing
