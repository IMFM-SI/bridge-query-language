import MathQL

open MathQL

private def usage : String :=
  "usage: mathql [--count] \"{ e | x ∈ Domain, condition }\"\n" ++
  "       mathql describe        -- JSON schema of all domains\n" ++
  "       mathql serve           -- read one query per line, write one JSON result per line"

private def resultLine : Except String (List Value) → String
  | .error e => "{\"error\": " ++ (Value.str e).toJson ++ "}"
  | .ok vs => "{\"ok\": [" ++ ", ".intercalate (vs.map Value.toJson) ++ "]}"

private partial def serve (stdin : IO.FS.Stream) : IO Unit := do
  let line ← stdin.getLine
  if line == "" then return ()  -- end of input
  let q := line.trim
  if q != "" then
    IO.println (resultLine (← MathQL.run q))
    (← IO.getStdout).flush
  serve stdin

def main (args : List String) : IO UInt32 := do
  match args with
  | ["serve"] => serve (← IO.getStdin); return 0
  | ["describe"] => IO.println catalogJson; return 0
  | "--count" :: [queryText] =>
    match ← MathQL.run queryText with
    | .error e => IO.eprintln s!"error: {e}"; return 1
    | .ok vs => IO.println vs.length; return 0
  | [queryText] =>
    match ← MathQL.run queryText with
    | .error e => IO.eprintln s!"error: {e}"; return 1
    | .ok vs => for v in vs do IO.println v.toJson
                return 0
  | _ => IO.eprintln usage; return 1
