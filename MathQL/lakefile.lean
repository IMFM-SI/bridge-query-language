import Lake
open Lake DSL

require leansqlite from git "git@github.com:leanprover/leansqlite.git" @ "main"
require leanpostgres from git "https://github.com/paulbutcher/leanpostgres.git" @ "v0.8.1"

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

-- TEMPORARY: M1 PostgreSQL driver checks. Not a default target, so a plain `lake build` does not
-- need libpq. See the header of `PgProbe.lean`.
lean_exe pgprobe where
  root := `PgProbe
