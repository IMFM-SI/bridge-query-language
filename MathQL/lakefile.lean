import Lake
open Lake DSL

require leansqlite from "../../leansqlite"

package MathQL where
  leanOptions := #[⟨`experimental.module, true⟩]

@[default_target]
lean_lib MathQL where
  precompileModules := true

@[default_target]
lean_exe mathql where
  root := `Main

lean_exe test where
  root := `Test
