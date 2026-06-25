import MathQL.Syntax

/-! A runtime parser for MathQL concrete syntax, turning a query string into a
`Query`. UTF-8 operators (`∈ ∧ ∨ ¬ ≠ ≤ ≥`) and their ASCII synonyms
(`in && || ! != <= >=`) are both accepted. -/

namespace MathQL.Parser

inductive Tok where
  | ident (s : String) | int (n : Int) | str (s : String) | tru | fls
  | lparen | rparen | lbrace | rbrace | comma | dot | pipe | inSym
  | and | or | not | eq | ne | le | lt | ge | gt | add | sub | mul
deriving Repr, BEq, Inhabited

private def isIdentStart (c : Char) : Bool := c.isAlpha || c == '_'
private def isIdentChar (c : Char) : Bool := c.isAlphanum || c == '_'

private partial def lex : List Char → Except String (List Tok)
  | [] => .ok []
  | c :: cs => do
    let one (t : Tok) := (t :: ·) <$> lex cs
    if c == ' ' || c == '\n' || c == '\t' || c == '\r' then lex cs
    else if c == '{' then one .lbrace
    else if c == '}' then one .rbrace
    else if c == '(' then one .lparen
    else if c == ')' then one .rparen
    else if c == ',' then one .comma
    else if c == '.' then one .dot
    else if c == '+' then one .add
    else if c == '-' then one .sub
    else if c == '*' then one .mul
    else if c == '∈' then one .inSym
    else if c == '∧' then one .and
    else if c == '∨' then one .or
    else if c == '¬' then one .not
    else if c == '≠' then one .ne
    else if c == '≤' then one .le
    else if c == '≥' then one .ge
    else if c == '|' then match cs with
      | '|' :: rest => (Tok.or :: ·) <$> lex rest
      | _ => one .pipe
    else if c == '&' then match cs with
      | '&' :: rest => (Tok.and :: ·) <$> lex rest
      | _ => .error "unexpected '&'"
    else if c == '<' then match cs with
      | '=' :: rest => (Tok.le :: ·) <$> lex rest
      | _ => one .lt
    else if c == '>' then match cs with
      | '=' :: rest => (Tok.ge :: ·) <$> lex rest
      | _ => one .gt
    else if c == '=' then match cs with
      | '=' :: rest => (Tok.eq :: ·) <$> lex rest
      | _ => one .eq
    else if c == '!' then match cs with
      | '=' :: rest => (Tok.ne :: ·) <$> lex rest
      | _ => one .not
    else if c == '"' then
      let body := cs.takeWhile (· != '"')
      let rest := (cs.dropWhile (· != '"')).drop 1
      (Tok.str (String.ofList body) :: ·) <$> lex rest
    else if c.isDigit then
      let digits := (c :: cs).takeWhile Char.isDigit
      let rest := (c :: cs).dropWhile Char.isDigit
      match (String.ofList digits).toInt? with
      | some n => (Tok.int n :: ·) <$> lex rest
      | none => .error s!"bad number {String.ofList digits}"
    else if isIdentStart c then
      let name := (c :: cs).takeWhile isIdentChar
      let rest := (c :: cs).dropWhile isIdentChar
      let tok := match String.ofList name with
        | "true" => Tok.tru
        | "false" => Tok.fls
        | "in" => Tok.inSym
        | s => Tok.ident s
      (tok :: ·) <$> lex rest
    else .error s!"unexpected character '{c}'"

/-- Parser state: the remaining tokens. -/
abbrev P := StateM (List Tok)

private def peek : P (Option Tok) := do return (← get).head?
private def advance : P Unit := do set (← get).tail

private def expect (t : Tok) : ExceptT String P Unit := do
  match ← peek with
  | some t' => if t' == t then advance else throw s!"expected {repr t}, got {repr t'}"
  | none => throw s!"expected {repr t}, got end of input"

mutual

private partial def parseExpr : ExceptT String P Expr := parseOr

private partial def parseOr : ExceptT String P Expr := do
  let mut e ← parseAnd
  while (← peek) == some .or do advance; e := .binop "or" e (← parseAnd)
  return e

private partial def parseAnd : ExceptT String P Expr := do
  let mut e ← parseCmp
  while (← peek) == some .and do advance; e := .binop "and" e (← parseCmp)
  return e

private partial def parseCmp : ExceptT String P Expr := do
  let l ← parseAdd
  let op? : Option String := match ← peek with
    | some .eq => some "eq" | some .ne => some "ne" | some .le => some "le"
    | some .lt => some "lt" | some .ge => some "ge" | some .gt => some "gt"
    | _ => none
  match op? with
  | some op => advance; return .binop op l (← parseAdd)
  | none => return l

private partial def parseAdd : ExceptT String P Expr := do
  let mut e ← parseMul
  repeat
    match ← peek with
    | some .add => advance; e := .binop "add" e (← parseMul)
    | some .sub => advance; e := .binop "sub" e (← parseMul)
    | _ => break
  return e

private partial def parseMul : ExceptT String P Expr := do
  let mut e ← parseUnary
  while (← peek) == some .mul do advance; e := .binop "mul" e (← parseUnary)
  return e

private partial def parseUnary : ExceptT String P Expr := do
  match ← peek with
  | some .not => advance; return .unop "not" (← parseUnary)
  | some .sub => advance; return .unop "neg" (← parseUnary)
  | _ => parsePostfix

private partial def parsePostfix : ExceptT String P Expr := do
  let mut e ← parseAtom
  while (← peek) == some .dot do
    advance
    match ← peek with
    | some (.ident f) => advance; e := .field e f
    | other => throw s!"expected field name after '.', got {repr other}"
  return e

private partial def parseAtom : ExceptT String P Expr := do
  match ← peek with
  | some (.int n) => advance; return .int n
  | some (.str s) => advance; return .str s
  | some .tru => advance; return .bool true
  | some .fls => advance; return .bool false
  | some (.ident s) => advance; return .var s
  | some .lparen =>
    advance
    let first ← parseExpr
    let mut items := [first]
    while (← peek) == some .comma do advance; items := items ++ [← parseExpr]
    expect .rparen
    return if items.length == 1 then first else .tuple items
  | other => throw s!"unexpected {repr other} in expression"

end

private def parseQuery : ExceptT String P Query := do
  expect .lbrace
  let result ← parseExpr
  expect .pipe
  let var ← match ← peek with
    | some (.ident v) => advance; pure v
    | other => throw s!"expected variable, got {repr other}"
  expect .inSym
  let domain ← match ← peek with
    | some (.ident d) => advance; pure d
    | other => throw s!"expected domain, got {repr other}"
  let condition ← match ← peek with
    | some .comma => advance; some <$> parseExpr
    | _ => pure none
  expect .rbrace
  return { result, var, domain, condition }

/-- Parse a MathQL query string. -/
def parse (s : String) : Except String Query := do
  let toks ← lex s.toList
  match (parseQuery.run.run toks) with
  | (.error e, _) => .error e
  | (.ok q, rest) =>
    if rest.isEmpty then .ok q
    else .error s!"unexpected trailing tokens: {repr rest}"

end MathQL.Parser
