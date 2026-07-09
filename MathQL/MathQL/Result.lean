namespace MathQL

abbrev Result := Except String

/-- Attach the evidence of success to a result -/
def Result.attach {α} (r : Result α) : Result { a : α // r = .ok a } :=
  match r with
  | .ok a => .ok ⟨a, rfl⟩
  | .error e => .error e
