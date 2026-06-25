# The MathQL language

This document describes the MathQL query language: its types, its terms with a
bidirectional typing judgement, its top-level queries, and how a query connects
to a database (the *realization*).

## Design goals

- **The simple fragment reads as ordinary mathematics.** A mathematician with
  no programming background should read the common case as set-builder
  notation:

  ```
  { g.chromatic_number | g ∈ SmallGraphs, g.is_planar ∧ g.girth > 4 }
  ```

- **The design follows standard programming-language theory.**

- **The notation mimics Lean 4 and uses UTF-8.**

## Types

```
τ ::= Int | Bool | String            base types
    | Option τ                       option
    | List τ                         list (ordered)
    | τ₁ × τ₂ × ⋯ × τₙ | Unit        product (Unit is the nullary product)
    | D                              a domain (named record type)
    | E                              an enumeration (named)
```

Records (domains `D`) and enumerations (`E`) are **named** and declared by the
schema. A domain abbreviates a record type `{ℓ₁ : τ₁, …}`; a field's type may be
another domain. An enumeration abbreviates a finite set of nullary constructors
`E = C₁ | ⋯ | Cₙ`. Records and enumerations are non-recursive, so every type is
a finite tree and type equality is structural.

`List τ` is an **ordered** sequence; it is the type of list-valued invariants
such as a degree sequence. It is distinct from the unordered multiset that a
*query* produces (see *Queries* below): that multiset is not a term type.

## Terms

A term denotes a value computed from a single object. Every type former has a
constructor and an eliminator.

| type | constructor | eliminator |
|------|-------------|------------|
| `τ₁ × ⋯ × τₙ` | `(e₁, …, eₙ)`, `()` | projection `e.i` (`i` a numeral) |
| domain `D` | `{ℓ := e, …}` | projection `e.ℓ` |
| `List τ` | `[]`, `e :: es`, sugar `[e₁,…,eₙ]` | `match` |
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
    | e = e | e ≠ e | e ≤ e | e < e | ⋯       -- comparisons
    | e + e | e - e | e * e | - e            -- arithmetic
    | e ∧ e | e ∨ e | ¬ e                     -- logic (synonyms: && || !)
    | (e : τ)                                -- ascription
```

A term is **not** a query and contains no comprehension. The dot is projection:
`e.i` positional, `e.ℓ` named. Leading-dot constructors (`.Polytopal`, `.none`,
`.some e`) are resolved against the expected type. Binding uses `:=`; `=` is the
equality test.

## Patterns and matching

Patterns are primitive; `match` is the eliminator for options, enumerations,
and lists, and destructures products and records. A pattern is typed by
`p : τ ⊣ Γ_p` — matching `p` against `τ` introduces the bindings `Γ_p`:

```
  ─────────────(P-Var)   ────────────(P-Wild)   ────────────(P-Enum)   (C a constructor of E)
  x : τ ⊣ x:τ            _ : τ ⊣ ·              .C : E ⊣ ·

  pᵢ : τᵢ ⊣ Γᵢ                          pᵢ : τᵢ ⊣ Γᵢ  (named fields)
  ─────────────────────────(P-Tuple)    ──────────────────────────(P-Record)
  (p₁,…,pₙ) : τ₁ × ⋯ × τₙ ⊣ Γ₁,…,Γₙ      {ℓᵢ := pᵢ} : {ℓᵢ : τᵢ} ⊣ Γ₁,…,Γₙ

  p : τ ⊣ Γ_p                                          p : τ ⊣ Γ_p   ps : List τ ⊣ Γ_ps
  ──────────────────────(P-Some)   ─────────────(P-None)   ──────────────(P-Nil)   ────────────────────────────(P-Cons)
  some p : Option τ ⊣ Γ_p          none : Option τ ⊣ ·     [] : List τ ⊣ ·         (p :: ps) : List τ ⊣ Γ_p, Γ_ps
```

Bindings are linear. `match` requires **exhaustive** coverage of the
scrutinee's type:

```
  Γ ⊢ e ⇒ τ      pᵢ : τ ⊣ Γᵢ      Γ, Γᵢ ⊢ eᵢ ⇐ σ      {p₁,…,pₙ} covers τ
  ──────────────────────────────────────────────────────────────────────(Match)
  Γ ⊢ match e with | p₁ ⇒ e₁ | ⋯ | pₙ ⇒ eₙ  ⇐  σ
```

`let p := e in e′` is the special case of a single irrefutable pattern.

## Queries

A **query** is the top-level form. It is a comprehension and is **not** a term:
it cannot nest, and it cannot appear as a subterm of an expression.

```
query ::= { e | x ∈ D, φ }
```

`D` is a domain. The variable `x` ranges over the objects of `D`; the condition
`φ` and the returned term `e` are terms over `x`. A query has its own typing
judgement, separate from the term judgement:

```
  D a domain with record type R_D    x : R_D ⊢ φ ⇐ Bool    x : R_D ⊢ e ⇒ σ
  ───────────────────────────────────────────────────────────────────────(Query)
  ⊢ { e | x ∈ D, φ }  ⤳  Bag σ
```

A query denotes a `Bag σ` — an **unordered multiset** of the return values of
the objects satisfying `φ`. The result is unordered because the query compiles
to a SQL `SELECT`, whose rows have no inherent order. `Bag` is the result of a
query and is not a type in the term language. Ordering and limiting the results
form a separate layer that wraps a query, to be added later.

An omitted condition `φ` means `true`.

## Contexts and typing judgements

A term context is `Γ ::= · | Γ, x : τ`, holding the query variable and any
pattern/`let` bindings. The typing judgement is bidirectional and
syntax-directed:

- synthesis `Γ ⊢ e ⇒ τ` — the type is computed from `e`;
- checking `Γ ⊢ e ⇐ τ` — `e` is checked against a given `τ`.

Eliminators, variables, literals, and operations synthesise; constructors check
(with a synthesising variant when all subterms synthesise); leading-dot
constructors check only. Ascription and the mode switch connect the modes.

```
  x : τ ∈ Γ                                          Γ ⊢ e ⇐ τ
  ──────────(Var)   ──────────(Int)  …               ──────────────(Asc)
  Γ ⊢ x ⇒ τ         Γ ⊢ n ⇒ Int                      Γ ⊢ (e : τ) ⇒ τ

  Γ ⊢ e ⇒ τ′    τ ≡ τ′
  ──────────────────────(Switch)
  Γ ⊢ e ⇐ τ
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

### Booleans, options, enums, lists

```
  Γ ⊢ b ⇐ Bool   Γ ⊢ e₁ ⇐ τ   Γ ⊢ e₂ ⇐ τ        Γ ⊢ e ⇐ τ                  ─────────────(None)
  ───────────────────────────────────────(If)    ─────────────────(Some)    Γ ⊢ none ⇐ Option τ
  Γ ⊢ if b then e₁ else e₂ ⇐ τ                    Γ ⊢ some e ⇐ Option τ

  C a constructor of E       ───────────────(Nil)   Γ ⊢ e ⇐ τ   Γ ⊢ es ⇐ List τ
  ──────────────(Enum)       Γ ⊢ [] ⇐ List τ        ──────────────────────────(Cons)
  Γ ⊢ .C ⇐ E                                        Γ ⊢ e :: es ⇐ List τ
```

(`match` eliminates options, enums, and lists; see *Patterns and matching*.)

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
elementwise, options and enums by constructor (recursively on payloads).
Ordering is on `Int` only.

## Missing values

A possibly-absent invariant has type `Option τ` — `diameter : Option Int`.
There is one notion of absence, `none`, stored as a nullable column. A query
handles it with `match`:

```
{ g | g ∈ SmallGraphs, match g.diameter with | some d ⇒ d < 5 | none ⇒ false }
```

In the realization an `Option τ` is a nullable column, `NULL ↦ none`, and a
`match` on it compiles to a `NULL` test.

## The realization

The types form a **signature**; a separate **realization** (model) connects it
to a concrete database. It annotates, per piece of the signature:

- a **domain** → a table (or view);
- a **field** → a column, a join path, or an expression, with a **codec**
  decoding the cell into the field's value (JSON text → `List Int`, etc.);
- an **enumeration** → a column with a **bijection** from constructors to stored
  tag values;
- an **`Option τ`** → a nullable column (`NULL ↦ none`);
- a **`List τ`** → a JSON cell or a related table, with an element codec.

A realization is **well-formed** when it is total over the signature (every
field realized) and each enumeration's constructor map is total and injective.

## Implementation

MathQL is a **standalone Lean package**. A query is parsed (with a parser
combinator library), elaborated by the bidirectional judgement above into an
intrinsically-typed term `Tm` indexed by `Ty` (so ill-typed queries are
rejected, with located errors), and compiled from `Tm` to a single SQL
`SELECT`. The result rows are decoded by the realization's codecs into the
returned values. There is no separate evaluator: every construct has a SQL
image.
