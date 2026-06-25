import MathQL

open MathQL

private def usage : String :=
  "usage: mathql [--count] \"{ e | x ∈ Domain, condition }\""

def main (args : List String) : IO UInt32 := do
  let (count, rest) := match args with
    | "--count" :: rest => (true, rest)
    | rest => (false, rest)
  match rest with
  | [queryText] =>
    match ← MathQL.run queryText with
    | .error e => IO.eprintln s!"error: {e}"; return 1
    | .ok values =>
      if count then
        IO.println values.length
      else
        for v in values do
          IO.println v.toJson
      return 0
  | _ => IO.eprintln usage; return 1
