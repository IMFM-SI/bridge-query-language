# The MathQL language

This document defines the MathQL query language: its concrete syntax, types,
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

- **The full language is orthogonal.** Every type former has a constructor and
  an eliminator; binders (`for`-style comprehension, `fold`, `let`, `match`,
  definitions) compose freely.

- **The notation mimics Lean 4 and uses UTF-8.** Where Lean has settled a
  notation we follow it; this also keeps the language close to its
  specification, which is written in Lean.

A guiding consequence of following Lean: product **types** are written with
`×` and product **terms** with parentheses, so `Int × Bool` is a type and
`(42, false)` is a term — different notation, no ambiguity.

## Types

```
τ ::= Int | Bool | String           base types
    | τ₁ × τ₂ × ⋯ × τₙ | Unit         product (Unit is the nullary product)
    | List τ                         list
    | Option τ                       option
    | D                              a domain (named record type)
    | E                              an enumeration (named, declared)
```

Records and enumerations are **named** and declared in a type environment `Δ`;
they are not written structurally at use sites. A domain `D` abbreviates a
record type `{ℓ₁ : τ₁, …}` (e.g. `SmallGraphs`); a field's type may be another
domain, which is how a join is typed. An enumeration is declared Lean-style,

```
inductive Polytopality | Polytopal | Faithful | Unfaithful
```

i.e. a finite set of nullary constructors (a sum of units). **Records and
enumerations are non-recursive**, so every type is a finite tree and type
equality `≡` is plain structural recursion.

There are no function types and no general sum types in the object language;
the only sum-shaped types are declared enumerations and `Option`.

## Terms

Every type former has a constructor and an eliminator:

| type | constructor | eliminator |
|------|-------------|------------|
| `τ₁ × ⋯ × τₙ` | `(e₁, …, eₙ)`, `()` | projection `e.i` (`i` a numeral) |
| domain `D` | (supplied by the database) `{ℓ := e, …}` | projection `e.ℓ` |
| `List τ` | `[]`, `e :: es`, sugar `[e₁,…,eₙ]` | `fold`, comprehension |
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
    | fold(e, e, fun x acc ⇒ e)              -- list recursor
    | { e | p ∈ e, φ }                       -- comprehension
    | f(e₁,…,eₙ)                             -- definition application
    | e = e | e ≠ e | e ≤ e | e < e | ⋯       -- comparisons
    | e + e | e - e | e * e | - e            -- arithmetic
    | e ∧ e | e ∨ e | ¬ e                     -- logic (synonyms: && || !)
    | (e : τ)                                -- ascription
```

Two Lean idioms carry their weight. The **dot is projection** — `e.i`
positional, `e.ℓ` named — exactly as in Lean. **Leading-dot constructors**
(`.Polytopal`, `.none`, `.some e`) are resolved against the expected type,
which is precisely the checking-mode rule below, so the notation and the
type discipline coincide. Binding is `:=` everywhere (`let`, record fields,
definitions), leaving `=` for the equality test, which reads as mathematics.

### Comprehension

`{ e | p ∈ c, φ }` is the math-facing list eliminator: for each element of the
collection `c` matching pattern `p` and satisfying `φ`, it collects `e`. The
source `c` is any expression of list type, so a domain (a list of records) and
a list-valued invariant are iterated alike, and comprehensions nest:

```
{ d | d ∈ g.degree_sequence, d > 2 }
```

It is definable from `fold` and the list monad; `fold` is the primitive.

## Patterns and matching

Patterns are a **primitive** notion, not sugar for projection — there is no
projection out of an option or an enum, so case analysis is the only
eliminator for those, and it is uniform across all formers. A pattern is typed
by `p : τ ⊣ Γ_p`, "matching `p` against `τ` introduces the bindings `Γ_p`":

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
and `fold` binders are patterns as well, typed by the same judgement.

## Definitions and the prelude

A **prelude** is a sequence of top-level definitions available to every query
— common aggregations and helpers — written in MathQL itself:

```
def count {α} (c : List α) : Int  := fold(c, 0, fun x acc ⇒ acc + 1)
def sum       (c : List Int) : Int := fold(c, 0, fun x acc ⇒ x + acc)
def all       (c : List Bool): Bool := fold(c, true, fun x acc ⇒ x ∧ acc)
```

Definitions are **abbreviations, not first-class functions**: a name `f` may be
*applied* — `f(e₁,…,eₙ)` — but is not a value, cannot be passed or partially
applied, and there is no arrow type in the object language. An application is
eliminated by substituting arguments into the body.

Definitions may be **prenex-polymorphic**: their schemes `∀ᾱ. (τ₁,…,τₙ) → σ`
live in a *separate* stratum, instantiated at each use site. `∀` and `→` occur
only in definition schemes; the object types `τ` that queries, attributes, and
the database speak remain monomorphic, arrow- and quantifier-free. This is
exactly Lean's polymorphic `def` with an implicit `{α}` over a first-order core.

Definitions are **non-recursive** and **total**: all iteration goes through
`fold`/comprehension, which are structural, so every program terminates. Each
definition is checked once, against its scheme, at the prelude (giving errors
there rather than at distant use sites), then elaborated at each use by
instantiation and substitution.

Handing query authors the prelude (`count`, `sum`, `max`, `any`, …) keeps
`fold` an implementation primitive they need not see.

## Contexts and environments

Three environments are in play:

- `Δ` — declared types: the domains (record types) and enumerations;
- `Σ` — the prelude: definition names with their schemes;
- `Γ` — the variable context, `Γ ::= · | Γ, x : τ`.

`Δ` and `Σ` are fixed for a query. `Γ` starts empty (the closed top-level query
mentions only domain and prelude names) and is extended by the binders, which
are the only way variables enter scope:

- `{ e | p ∈ c, φ }` checks `e` and `φ` under `Γ, Γ_p` where `c : List τ` and `p : τ ⊣ Γ_p`;
- `fold(c, z, fun x acc ⇒ s)` checks `s` under `Γ, x:τ, acc:σ`;
- `let p := e₁ in e₂` checks `e₂` under `Γ, Γ_p`;
- a definition checks its body under its parameters.

Lookup `Γ(x)` returns the innermost binding; inner binders shadow outer ones.

## Typing judgements

The system is bidirectional and syntax-directed:

- synthesis `Γ ⊢ e ⇒ τ` — the type is computed from `e`;
- checking `Γ ⊢ e ⇐ τ` — `e` is checked against a given `τ`.

Eliminators, variables, literals, operations, `fold`, comprehensions, `let`,
and applications synthesise; constructors check (with a synthesising variant
when all subterms synthesise); leading-dot constructors check only. Ascription
and the mode switch connect the modes.

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

### Booleans, lists, fold, comprehension

```
  Γ ⊢ b ⇐ Bool   Γ ⊢ e₁ ⇐ τ   Γ ⊢ e₂ ⇐ τ        ───────────────(Nil)   Γ ⊢ e ⇐ τ   Γ ⊢ es ⇐ List τ
  ───────────────────────────────────────(If)    Γ ⊢ [] ⇐ List τ        ──────────────────────────(Cons)
  Γ ⊢ if b then e₁ else e₂ ⇐ τ                                          Γ ⊢ e :: es ⇐ List τ

  Γ ⊢ c ⇒ List τ   Γ ⊢ z ⇒ σ   Γ, x:τ, acc:σ ⊢ s ⇒ σ        Γ ⊢ c ⇒ List τ   p : τ ⊣ Γ_p   Γ,Γ_p ⊢ φ ⇐ Bool   Γ,Γ_p ⊢ e ⇒ σ
  ────────────────────────────────────────────────(Fold)    ───────────────────────────────────────────────────────────────(Comp)
  Γ ⊢ fold(c, z, fun x acc ⇒ s) ⇒ σ                          Γ ⊢ { e | p ∈ c, φ } ⇒ List σ
```

(An omitted `φ` means `true`.)

### Definitions, let, ascription

```
  (f : ∀ᾱ. (τ₁,…,τₙ) → σ) ∈ Σ    τᵢ' = τᵢ[ᾱ ↦ ρ̄]    Γ ⊢ eᵢ ⇐ τᵢ'
  ─────────────────────────────────────────────────────────────────(App)
  Γ ⊢ f(e₁,…,eₙ) ⇒ σ[ᾱ ↦ ρ̄]

  Γ ⊢ e₁ ⇒ τ₁    p : τ₁ ⊣ Γ_p    Γ, Γ_p ⊢ e₂ ⇒ τ₂
  ──────────────────────────────────────────────────(Let)
  Γ ⊢ let p := e₁ in e₂ ⇒ τ₂
```

(The instantiation `ρ̄` in `App` is determined by checking the arguments; `let`
also has a checking variant that checks `e₂ ⇐ τ`.)

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

A possibly-absent invariant such as `diameter` keeps a total type (`Int`,
never `Option Int`). "Missing" is one semantic dimension, not a type: each `τ`
is interpreted in a pointed domain `⟦τ⟧⊥`, operations are strict in `⊥`, the
connectives use Kleene's strong three-valued tables, and a query's final
keep/drop is a caller-chosen collapse `Bool⊥ → Bool` (sound: keep only `true`;
complete: keep `true` and `⊥`). No typing rule mentions nullability.

This is distinct from `Option`, which is **absent by design** — a value the
mathematics genuinely may lack. The two readings of a `NULL` cell are told
apart by the attribute's declared type (see below): a total `τ` reads `NULL`
as `⊥`, an `Option τ` reads it as `none`.

## The realization

The types above form a **signature**; how it connects to a database is a
separate **realization** (model), so one signature can be realized by several
backends (a stored SQLite file, or a database generated on the fly). The
realization annotates, per piece of the signature:

- a **domain** → a table (or view, or generator);
- a **field** → a column, a join path, or an expression, with a **codec**
  decoding the cell into the field's value (e.g. JSON text → `List Int`);
- an **enumeration** → a column together with a **bijection** from constructors
  to stored tag values (the stored form is arbitrary and must be given
  explicitly, never assumed equal to the constructor name);
- an **`Option τ`** → a nullable column (`NULL` ↦ `none`);
- a **`List τ`** → a related table or a JSON cell, with an element codec.

A realization is **well-formed** when it is total over the signature (every
field realized) and each enumeration's constructor map is total and injective —
all decidable from the signature, with no data. Whether a database *instance*
conforms (only mapped tags, non-null where the type is total) is a separate,
optional integrity check; data is checked against the declared types, never the
source of them.

Each type former keeps a clear relational image — record → row, product →
columns, list → related table or JSON, enum → tag column, option → nullable
column — which is why the language admits no type former without one.

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
| semantics | `Tm.interpret`, `Query.interpret`; the `⊥`/Kleene reading is the lifted-domain extension |
| prelude definition | a Lean `def` with implicit `{α}` over the first-order core |

The bidirectional checker is therefore an **elaborator**: a parsed query
becomes a well-typed `Tm`, or a located type error is reported, and the
compiler and evaluator consume the typed term — so their otherwise-impossible
cases do not arise, and implementation and specification stay in step.
