/-! Runtime result values and their JSON rendering. -/

namespace MathQL

/-- A value produced by running a query: what gets rendered to the caller. -/
inductive Value where
  | int (n : Int)
  | bool (b : Bool)
  | str (s : String)
  | null
  | list (items : List Value)
  | obj (fields : List (String × Value))
deriving Repr, Inhabited

private def escapeString (s : String) : String :=
  s.foldl (init := "") fun acc c =>
    acc ++ match c with
      | '"' => "\\\""
      | '\\' => "\\\\"
      | '\n' => "\\n"
      | '\t' => "\\t"
      | _ => c.toString

/-- Render a value as JSON. -/
partial def Value.toJson : Value → String
  | .int n => toString n
  | .bool b => if b then "true" else "false"
  | .str s => "\"" ++ escapeString s ++ "\""
  | .null => "null"
  | .list items => "[" ++ ", ".intercalate (items.map Value.toJson) ++ "]"
  | .obj fields =>
    "{" ++ ", ".intercalate (fields.map fun (k, v) => "\"" ++ k ++ "\": " ++ v.toJson) ++ "}"

end MathQL
