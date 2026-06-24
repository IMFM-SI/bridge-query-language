import QueryLanguage.Core

/-! The surface syntax of the high-level DSL, which is split into two layers:

  * a **generic, structural core** (this module): It provides the syntax
    categories `query_tm` and `query_query`, the entry-point notations `⟦tm| …
    ⟧`, `⟦q| … ⟧` and `>> … <<`, and the elaboration of the generic structural
    constructs (unit, pairing, projections, conjunction, etc).

  * an **instance-specific layer**, contributed separately for each concrete
    schema (see `QueryLanguage.Peano.Schema` for an example): An instance
    extends the `query_tm`/`query_query` categories with syntax for *its*
    operations, attributes and predicates, and registers its `macro_rules`.
-/

namespace DSL

  /-- Structural term syntax. Instances extend this with their operations. -/
  declare_syntax_cat query_tm
  syntax "()"                  : query_tm
  syntax query_tm "," query_tm : query_tm
  syntax "fst" query_tm        : query_tm
  syntax "snd" query_tm        : query_tm
  syntax "(" query_tm ")"      : query_tm

  /-- Structural query syntax. Instances extend this with their predicates. -/
  declare_syntax_cat query_query
  syntax "false"                      : query_query
  syntax "true"                       : query_query
  syntax query_query "&&" query_query : query_query
  syntax "(" query_query ")"          : query_query

  /-- Entry point that turns DSL term syntax into a `Tm`. -/
  syntax "⟦tm| " query_tm "⟧" : term
  /-- Entry point that turns DSL query syntax into a `Query`. -/
  syntax "⟦q| "  query_query "⟧" : term
  /-- Friendly surface syntax for writing a query inline. -/
  syntax ">> " query_query " <<" : term

  -- Elaboration of the structural term constructs.
  macro_rules
    | `(⟦tm| ()⟧)                       => `(Tm.tt)
    | `(⟦tm| $t:query_tm, $u:query_tm⟧) => `(Tm.pair ⟦tm| $t⟧ ⟦tm| $u⟧)
    | `(⟦tm| fst $t:query_tm⟧)          => `(Tm.fst ⟦tm| $t⟧)
    | `(⟦tm| snd $t:query_tm⟧)          => `(Tm.snd ⟦tm| $t⟧)
    | `(⟦tm| ($t:query_tm)⟧)            => `(⟦tm| $t⟧)

  -- Elaboration of the structural query constructs.
  macro_rules
    | `(⟦q| false⟧)                            => `(Query.false)
    | `(⟦q| true⟧)                             => `(Query.true)
    | `(⟦q| $p:query_query && $q:query_query⟧) => `(Query.conj ⟦q| $p⟧ ⟦q| $q⟧)
    | `(⟦q| ($p:query_query)⟧)                 => `(⟦q| $p⟧)
    | `(>> $q:query_query <<)                  => `(⟦q| $q⟧)

end DSL
