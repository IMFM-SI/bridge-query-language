# Backend differences

This file records concrete examples and verification evidence for [DESIGN.md](DESIGN.md), especially CORE-03 and TYPE-03. It does not define a second implementation plan. Differences are expected, not defects to normalize; shared postprocessing remains independent.

Status: the decisions below are settled requirements. SQLite compilation and postprocessing behavior were inspected in the current Lean sources; PostgreSQL integration tests have not yet been run. Add tested versions and test references as implementation proceeds.

## Division by zero

Minimal request:

```json
{"domains": [], "output": [["value", "1 / 0"]]}
```

| Execution context | Required behavior |
| --- | --- |
| SQLite SQL | Preserve existing native division: the cell is NULL and decodes to JSON `null`. |
| PostgreSQL SQL | Native division raises an error; return an error response for the query, not a row with a substituted null. |
| Lean postprocessing | Preserve the existing interpreter: division by zero fails evaluation, and `evalPostprocess` converts that entry's failure to JSON `null`. |

Do not wrap PostgreSQL division in `NULLIF` or catch its error to manufacture a value. A valid request following a failed SQL query must still work.

## Comparisons of lists and products

Minimal request:

```json
{"domains": [], "output": [["greater", "[2, 2] > [2, 10]"]]}
```

| Execution context | Comparison | Expected value in this example |
| --- | --- | --- |
| SQLite SQL | Existing canonical JSON-text comparison | `true` |
| PostgreSQL SQL | Native JSONB comparison (equal-length arrays compare elements) | `false` |
| Lean postprocessing | Existing comparison of compressed JSON text | `true` |

Use the DBMS's comparison operators for equality and ordering on its chosen representation. All PostgreSQL lists and products use native JSONB comparison, including nested collections. Do not cast them to text for comparison or introduce custom elementwise helpers to make either backend agree with the other.

JSONB arrays compare length first, then elements for equal lengths. For example, `[9] < [1, 2]` is expected to be `true` under JSONB ordering, whereas SQLite JSON-text ordering gives `false`. This also differs from native PostgreSQL SQL-array ordering. Use JSONB behavior as-is; do not emulate SQL arrays. See [PostgreSQL JSONB ordering](https://www.postgresql.org/docs/current/datatype-json.html#JSON-INDEXING). These expectations still need integration tests.

Store an absent whole collection as SQL NULL, a present empty collection as `[]`, and an absent component as JSON null inside its array. On projection, convert a JSON null component back to SQL NULL so MathQL presence tests see absence. This conversion does not alter native comparisons of whole JSONB collections.

## Postprocessing is independent

SQL evaluation and Lean postprocessing do not have to agree on arithmetic, structured comparisons or error propagation. In particular, **SQLite already differs from postprocessing** for a division-by-zero expression inside a list or tuple. Preserve this difference.

Minimal SQLite request evaluating the same expression in both stages:

```json
{"domains": [], "output": [["sql_value", "[1 / 0, 1]"]], "postprocess": [["post_value", "[1 / 0, 1]"]]}
```

Expected response from the current implementation, based on the code paths below:

```json
{"rows": [[["sql_value", [null, 1]], ["post_value", null]]]}
```

The tuple expression `(1 / 0, 1)` has the same distinction: SQLite returns `[null, 1]`, while the whole postprocessing entry becomes `null`.

Code evidence:

- `MathQL/MathQL/Compile.lean`, `compileExpr`: both `.list` and `.tuple` compile to `.jsonArray`; division compiles to the ordinary binary operator.
- `MathQL/MathQL/SQLExpr.lean`, `renderBinop` and `renderExpr`: this produces `json_array((1 / 0), 1)`. SQLite's division returns SQL NULL, and `json_array` retains it as a null element alongside `1`.
- `MathQL/MathQL/Execute.lean`, `decodeCell`: parses the resulting JSON text, preserving `[null, 1]`.
- In that same file, `evalBinaryOp` throws on a zero divisor. The `.list` and `.tuple` branches of `evalPostExpr` use `mapM`, so that error aborts evaluation of the entire collection. `evalPostprocess` then converts the failed entry to JSON `null`; it does not catch errors separately for each element.

This is an evaluation-error distinction, not a rule that every collection containing a null collapses. A previously decoded null used as an element can remain a null element when no evaluation error is raised. PostgreSQL SQL division by zero still raises a query error under the separate decision above. No changes to postprocessing or agreement between SQL and postprocessing are required.

## Additional differences to verify

As implementation proceeds, add minimal queries, actual outcomes, tested versions and test references for null sort order, integer range/overflow, text collation, JSONB projection and presence tests, and nested collection comparisons. Keep untested expectations clearly distinguished from executed regression results.
