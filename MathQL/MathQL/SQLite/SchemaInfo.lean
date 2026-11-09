import MathQL.Database
import SQLite

/-! Physical column discovery on SQLite, for choosing generated aliases that no column of the
database captures. Moved from `Main`. -/

namespace MathQL.SQLite

/-- The names of the columns of `table`. -/
def columnNames (db : _root_.SQLite) (table : String) : IO (List String) := do
  let stmt ← db.prepare "SELECT name FROM pragma_table_info(?)"
  stmt.bindText 1 table
  let names ← (stmt.resultsAs String).toArray
  return names.toList

/-- A name is a safe alias when no table of `database` has a column of that name.
    `rowid`, `oid` and `_rowid_` name a column that `pragma_table_info` omits. -/
def safeAliasPredicate (db : _root_.SQLite) (database : Database) : IO (String → Bool) := do
  let columns ← database.domain.mapM fun (_, sch) => columnNames db sch.table
  let taken := ("rowid" :: "oid" :: "_rowid_" :: columns.flatten).map String.toLower
  return fun s => !taken.contains s.toLower

end MathQL.SQLite
