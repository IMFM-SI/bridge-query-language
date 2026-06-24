# The MathQL language

This document describes the MathQL query language: its concrete syntax, types,
terms, contexts, and a bidirectional typing judgement, together with how a
program connects to a database (the *realization*) and how it corresponds to
the Lean specification under `lean/`.

## Design goals

- **The simple fragment reads as ordinary mathematics.** A mathematician with
  no programming background should read the common case as set-builder
  notation:

  ```
  { g.chromatic_number | g ∈ SmallGraphs, g.is_planar ∧ g.girth > 4 }
  ```

- **The design follows standard PL theory and practice of implementation**
  (the Edinburgh & CMU school of programming languages).

- **The notation mimics Lean 4 and uses UTF-8.**

## Types

```
τ ::= Int | Bool | String            base types
    | τ₁ × τ₂ × ⋯ × τₙ | Unit        product (Unit is the nullary product)
    | List τ                         list
    | Option τ                       option
    | D                              a domain (named record type)
    | E                              an enumeration (named, declared)
```


Records and enumerations are **named** and declared in a type environment `Δ`.
A domain `D` abbreviates a record type `{ℓ₁ : τ₁, …}` (e.g. `SmallGraphs`); a field's type may be another domain, but recursive types are not allowed. An enumeration `E` abbreviates
a sum of nullary constructors `t₁ | ... | tᵢ`.

There are no function types and no general sum types in the object language;
the only sum-shaped types are declared enumerations and `Option`.

## Terms

Every type former has a constructor and an eliminator:

| type | constructor | eliminator |
|------|-------------|------------|
| `τ₁ × ⋯ × τₙ` | `(e₁, …, eₙ)`, `()` | projection `e.i` (`i` a numeral) |
| domain `D` | (supplied by the database) `{ℓ := e, …}` | projection `e.ℓ` |
| `List τ` | `[]`, `e :: es`, sugar `[e₁,…,eₙ]` | comprehension, aggregates |
| `Option τ` | `some e`, `none` | `match` |
| enum `E` | `.C` (leading dot) | `match` |
| `Bool` | `true`, `false` | `if e then e₁ else e₂` |

```
e ::= x | n | "s" | true | false
    | (e₁,…,eₙ) | e.i                       -- product
    | {ℓ₁ := e₁, …} | e.ℓ                    -- record
    | [] | e :: e | [e₁,…,eₙ]                -- list
    | some e | none | .C                     -- option / enum constructors
    | if e then e else e                     -- conditional
    | match e with | p ⇒ e | ⋯               -- case analysis
    | let p := e in e                        -- local binding
    | { e | p ∈ e, φ }                       -- comprehension
    | f(e₁,…,eₙ)                             -- aggregate or definition application
    | e = e | e ≠ e | e ≤ e | e < e | ⋯       -- comparisons
    | e + e | e - e | e * e | - e            -- arithmetic
    | e ∧ e | e ∨ e | ¬ e                     -- logic (synonyms: && || !)
    | (e : τ)                                -- ascription
```

The **dot is projection**: `e.i` positional, `e.ℓ` named. **Leading-dot
constructors** (`.Polytopal`, `.none`, `.some e`) are resolved against the
expected type (the checking-mode rule below). Binding uses `:=` (`let`, record
fields, definitions); `=` is the equality test.

### Comprehension

`{ e | p ∈ c, φ }` is the list eliminator: for each element of the collection
`c` matching pattern `p` and satisfying `φ`, it collects `e`. The source `c` is
any expression of list type, so a domain (a list of records) and a list-valued
invariant are iterated alike, and comprehensions nest:

```
{ d | d ∈ g.degree_sequence, d > 2 }
```

Comprehension is a primitive. The other eliminators of `List τ` are the
aggregates `count`, `sum`, `max`, `min`, `any`, `all`; like comprehension they
compile directly to SQL.

## Patterns and matching

Patterns are a **primitive** notion; `match` is the eliminator for options and
enumerations, and applies to products and records too. A pattern is typed by
`p : τ ⊣ Γ_p` — matching `p` against `τ` introduces the bindings `Γ_p`:

```
  ─────────────(P-Var)     ────────────(P-Wild)     ────────────(P-Enum)   (C a constructor of E)
  x : τ ⊣ x:τ              _ : τ ⊣ ·                .C : E ⊣ ·

  pᵢ : τᵢ ⊣ Γᵢ                          pᵢ : τᵢ ⊣ Γᵢ  (named fields)
  ─────────────────────────(P-Tuple)    ──────────────────────────(P-Record)
  (p₁,…,pₙ) : τ₁ × ⋯ × τₙ ⊣ Γ₁,…,Γₙ      {ℓᵢ := pᵢ} : {ℓᵢ : τᵢ} ⊣ Γ₁,…,Γₙ

  p : τ ⊣ Γ_p
  ──────────────────────(P-Some)        ──────────────────(P-None)
  some p : Option τ ⊣ Γ_p                none : Option τ ⊣ ·
```

Bindings are linear (a variable occurs at most once in a pattern). `match` is
the primitive eliminator, requiring **exhaustive** coverage of the scrutinee's
type:

```
  Γ ⊢ e ⇒ τ      pᵢ : τ ⊣ Γᵢ      Γ, Γᵢ ⊢ eᵢ ⇐ σ      {p₁,…,pₙ} covers τ
  ──────────────────────────────────────────────────────────────────────(Match)
  Γ ⊢ match e with | p₁ ⇒ e₁ | ⋯ | pₙ ⇒ eₙ  ⇐  σ
```

`let p := e in e′` is the special case where `p` is a single **irrefutable**
pattern (variable, tuple, record), so coverage is automatic. The comprehension
binder is a pattern as well, typed by the same judgement.

## Definitions and the prelude

A **prelude** is a sequence of top-level definitions available to every query —
common helper abbreviations:

```
def square (n : Int) : Int := n * n
```

A definition is an **abbreviation**: an application `f(e₁,…,eₙ)` elaborates by
substituting the given arguments for its parameters in the body. Definitions are
**monomorphic** — each has fixed parameter and result types; there is no
polymorphism and no arrow type — and **non-recursive**.

The aggregates `count`, `sum`, `max`, `min`, `any`, `all` are built-in
primitives, not definitions; like comprehension they compile to SQL.

## Contexts and environments

Two things are in play:

- `Δ` — the declared types: domains (record types) and enumerations, supplied by the schema;
- `Γ` — a single context of definitions and variable bindings.

The prelude is not a separate environment: its definitions are the first entries
of `Γ`, whatever is defined first. The binders extend `Γ` and are the only
further way names enter scope:

- a definition adds its name (with its parameter and result types) to `Γ`;
- `{ e | p ∈ c, φ }` checks `e` and `φ` under `Γ, Γ_p` where `c : List τ` and `p : τ ⊣ Γ_p`;
- `let p := e₁ in e₂` checks `e₂` under `Γ, Γ_p`.

Lookup returns the innermost binding; inner binders shadow outer ones.

## Typing judgements

The system is bidirectional and syntax-directed:

- synthesis `Γ ⊢ e ⇒ τ` — the type is computed from `e`;
- checking `Γ ⊢ e ⇐ τ` — `e` is checked against a given `τ`.

Eliminators, variables, literals, operations, comprehensions, `let`, and
applications synthesise; constructors check (with a synthesising variant when
all subterms synthesise); leading-dot constructors check only. Ascription and
the mode switch connect the modes.

```
  x : τ ∈ Γ                                          Γ ⊢ e ⇐ τ
  ──────────(Var)   ──────────(Int)  …               ──────────────(Asc)
  Γ ⊢ x ⇒ τ         Γ ⊢ n ⇒ Int                      Γ ⊢ (e : τ) ⇒ τ

  Γ ⊢ e ⇒ τ′    τ ≡ τ′
  ──────────────────────(Switch)        D a domain with record type R_D
  Γ ⊢ e ⇐ τ                             ─────────────────────────────────(Domain)
                                        Γ ⊢ D ⇒ List R_D
```

### Products and records

```
  Γ ⊢ eᵢ ⇐ τᵢ                       Γ ⊢ eᵢ ⇒ τᵢ                  Γ ⊢ e ⇒ τ₁ × ⋯ × τₙ   1≤i≤n
  ───────────────────(×-I⇐)         ───────────────────(×-I⇒)    ──────────────────────────────(×-E)
  Γ ⊢ (e₁,…) ⇐ τ₁×⋯×τₙ              Γ ⊢ (e₁,…) ⇒ τ₁×⋯×τₙ          Γ ⊢ e.i ⇒ τᵢ

  Γ ⊢ eᵢ ⇐ τᵢ                            Γ ⊢ e ⇒ {…, ℓ : τ, …}
  ───────────────────────────(Rec-I)     ──────────────────────(Rec-E)
  Γ ⊢ {ℓᵢ := eᵢ} ⇐ {ℓᵢ : τᵢ}              Γ ⊢ e.ℓ ⇒ τ
```

### Booleans, lists, comprehension, aggregates

```
  Γ ⊢ b ⇐ Bool   Γ ⊢ e₁ ⇐ τ   Γ ⊢ e₂ ⇐ τ        ───────────────(Nil)   Γ ⊢ e ⇐ τ   Γ ⊢ es ⇐ List τ
  ───────────────────────────────────────(If)    Γ ⊢ [] ⇐ List τ        ──────────────────────────(Cons)
  Γ ⊢ if b then e₁ else e₂ ⇐ τ                                          Γ ⊢ e :: es ⇐ List τ

  Γ ⊢ c ⇒ List τ   p : τ ⊣ Γ_p   Γ,Γ_p ⊢ φ ⇐ Bool   Γ,Γ_p ⊢ e ⇒ σ
  ───────────────────────────────────────────────────────────────(Comp)
  Γ ⊢ { e | p ∈ c, φ } ⇒ List σ

  Γ ⊢ c ⇒ List τ        Γ ⊢ c ⇒ List Int                Γ ⊢ c ⇒ List Bool
  ──────────────(Count)  ───────────────(Sum, Max, Min)   ──────────────(Any, All)
  Γ ⊢ count(c) ⇒ Int     Γ ⊢ sum(c) ⇒ Int                Γ ⊢ any(c) ⇒ Bool
```

(An omitted `φ` means `true`.)

### Definitions, let, ascription

```
  (f with parameters (τ₁,…,τₙ) and result σ) ∈ Γ    Γ ⊢ eᵢ ⇐ τᵢ
  ──────────────────────────────────────────────────────────────(App)
  Γ ⊢ f(e₁,…,eₙ) ⇒ σ

  Γ ⊢ e₁ ⇒ τ₁    p : τ₁ ⊣ Γ_p    Γ, Γ_p ⊢ e₂ ⇒ τ₂
  ──────────────────────────────────────────────────(Let)
  Γ ⊢ let p := e₁ in e₂ ⇒ τ₂
```

(`let` also has a checking variant that checks `e₂ ⇐ τ`.)

### Equality, ordering, arithmetic, logic

```
  Γ ⊢ e₁ ⇒ τ    Γ ⊢ e₂ ⇐ τ              Γ ⊢ e₁ ⇐ Int   Γ ⊢ e₂ ⇐ Int
  ─────────────────────────(Eq)         ──────────────────────────────(Ord)   for ≤ < > ≥
  Γ ⊢ e₁ = e₂ ⇒ Bool    (also ≠)        Γ ⊢ e₁ ≤ e₂ ⇒ Bool

  Γ ⊢ e₁ ⇐ Int   Γ ⊢ e₂ ⇐ Int           Γ ⊢ e ⇐ Int        Γ ⊢ e₁ ⇐ Bool  Γ ⊢ e₂ ⇐ Bool       Γ ⊢ e ⇐ Bool
  ──────────────────────────────(Arith)  ──────────────(Neg) ────────────────────────────(Logic) ─────────────(Not)
  Γ ⊢ e₁ + e₂ ⇒ Int   for + - *          Γ ⊢ - e ⇒ Int       Γ ⊢ e₁ ∧ e₂ ⇒ Bool   for ∧ ∨        Γ ⊢ ¬ e ⇒ Bool
```

Equality is defined for every `τ` by structural recursion: base types by their
primitive equality, products componentwise, records fieldwise, lists
elementwise, options and enums by constructor (and recursively on payloads).

## Missing values

A possibly-absent invariant has type `Option τ` — `diameter : Option Int`.
There is one notion of absence: whether the value is undefined by the
mathematics or merely not computed, it is `none`. A query handles it explicitly
with `match`:

```
{ g | g ∈ SmallGraphs, match g.diameter with | some d ⇒ d < 5 | none ⇒ false }
```

In the realization an `Option τ` is a nullable column, `NULL ↦ none`, and a
`match` on it compiles to a `NULL` test.

## The realization

The types form a **signature**; a separate **realization** (model) connects it
to a concrete database — a stored SQLite file or one generated on demand. The
realization annotates, per piece of the signature:

- a **domain** → a table (or view, or generator);
- a **field** → a column, a join path, or an expression, with a **codec**
  decoding the cell into the field's value (e.g. JSON text → `List Int`);
- an **enumeration** → a column with a **bijection** from constructors to stored
  tag values;
- an **`Option τ`** → a nullable column (`NULL` ↦ `none`);
- a **`List τ`** → a related table or a JSON cell, with an element codec.

A realization is **well-formed** when it is total over the signature (every
field realized) and each enumeration's constructor map is total and injective.
Whether a database *instance* conforms (only mapped tags, non-null where the
type is total) is a separate, optional integrity check.

## Correspondence with the Lean development

MathQL is implemented in, and specified by, the Lean development under `lean/`
(`QueryLanguage/Core.lean`, `QueryLanguage/DSL.lean`).

| MathQL concept | Lean |
|----------------|------|
| types `τ` | `Ty` |
| domains / records | `DBSignature` |
| operations (`+`, `≤`, `=`, …) | `OpSignature` |
| comparisons used as conditions | `PredSignature` |
| typed terms | `Tm` |
| `typecheck` | elaboration of concrete syntax into `Tm` (extrinsic → intrinsic) |
| the realization | `DBModel`, `GroundModel`, `OpModel`, `PredModel` |
| query / comprehension | `Query` and the surface in `DSL.lean` |
| reference semantics | `Tm.interpret`, `Query.interpret` |
| prelude definition | a monomorphic Lean `def` |

The bidirectional checker is an **elaborator**: a parsed query becomes a
well-typed `Tm`, or a located type error is reported. The implementation
compiles `Tm` to SQL; `interpret` is the reference semantics the compilation is
checked against, not a runtime path. Every construct has a SQL image, so no
independent evaluator is needed.
