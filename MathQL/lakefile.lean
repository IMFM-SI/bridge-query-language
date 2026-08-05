import Lake
open Lake DSL

require leansqlite from git "git@github.com:leanprover/leansqlite.git" @ "main"

package MathQL where
  leanOptions := #[⟨`experimental.module, true⟩, ⟨`autoImplicit, false⟩]

@[default_target]
lean_lib MathQL where
  precompileModules := true

@[default_target]
lean_exe mathql where
  root := `Main

@[default_target]
lean_exe test where
  root := `Test
