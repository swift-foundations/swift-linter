# Thread E Phase 2 — Public-DSL rename catalog (swift-linter + swift-linter-primitives)

> **Status**: AWAITING PRINCIPAL DISPOSITION. Phase 3 execution does
> NOT begin until each row below is dispositioned. Do NOT apply
> renames inline.

## Scope and lens

Per `HANDOFF-thread-e-compound-identifier-sweep.md`, Phase 2 catalogs
every compound identifier and compound type name on the **public DSL**
surface of swift-linter and swift-linter-primitives — the
consumer-observable engine + L1 primitives surface. Pack-internal
helpers and CLI-internal helpers are out of scope (closed in Phase 1
or surfaced as scope ambiguities below).

The maximal-reuse lens per `project_linter_maximal_ecosystem_reuse.md`
asks every row: does an existing ecosystem typed primitive cover the
role this raw type plays at the site? If yes, the rename may collapse
to a typed-primitive adoption (Shape B); if no, the rename is
structural (Shape A).

Post-Phase-1 dogfeed baseline:

| Pack | compound identifier | compound type name | Total |
|------|---:|---:|---:|
| swift-linter-primitives | 6 (all public) | 0 | 6 |
| swift-linter | 15 public + 33 internal | 3 public + 5 internal | 56 |
| **Total in catalog** | **21** | **3** | **24** |

Plus 1 carry-forward from Phase 1 escalation
(`Lint.Rule.Bundle.brandOwner` on swift-primitives-linter-rules,
public DSL but rule-pack-owned — out of HANDOFF Phase 2 declared
scope but listed at end for principal awareness).

## Scope ambiguities surfaced (class-(c) per [SUPER-005])

The HANDOFF Phase 2 scope is "swift-linter + swift-linter-primitives
public DSL." Two scope ambiguities surfaced during enumeration:

1. **33 swift-linter compound-identifier findings at `internal`
   visibility**. The HANDOFF's Phase 1 mechanical scope was rule-packs
   (`swift-linter-rules`, `swift-institute-linter-rules`,
   `swift-primitives-linter-rules`) — swift-linter itself was NOT
   listed for Phase 1. Phase 2 explicitly scoped to public DSL. The
   33 internal findings on swift-linter are neither bucket. Treatment
   options: (a) extend Phase 1 to swift-linter internals (apply the
   same `internal → fileprivate` visibility-shift pattern that closed
   30 of 41 institute-linter-rules findings); (b) catalog them as
   Phase 2 review-only items; (c) defer to a separate Thread F+
   dispatch. Recommended: extend Phase 1 mechanical
   (visibility-shift) once principal authorizes — this is a low-risk
   30-second-per-file change with no public API impact. NOT included
   below pending disposition.

2. **`Lint.Rule.Bundle.brandOwner` at public visibility on
   swift-primitives-linter-rules**. Phase 1's HANDOFF explicitly
   scoped to "pack-internal compound identifiers ... no public API
   impact" — `brandOwner` is `public static let`. It belongs in
   Phase 2 by shape (public DSL compound identifier) but Phase 2's
   declared scope was swift-linter + swift-linter-primitives, not
   rule-packs. Treatment: surface as cross-pack supplemental row at
   end of catalog; principal may include or DEFER.

---

## swift-linter-primitives (6 rows)

### Row 1 — `Lint.Configuration.disabledRuleIDs` at `Sources/Linter Primitives/Lint.Configuration.swift:76`

**Current shape**: `public let disabledRuleIDs: [Lint.Rule.ID]`
**Compound rule**: [API-NAME-002] (compound identifier — "disabled" + "Rule" + "IDs")

**Proposed shape A (rename only)**: `public let disabled: [Lint.Rule.ID]`
— drops "RuleIDs" suffix; the typed `[Lint.Rule.ID]` already says
"rule IDs" at the type level (namespace-implicit-prefix sub-rule).

**Proposed shape B (rename + collection change)**: `public let disabled: Set<Lint.Rule.ID>`
— same rename as A AND changes `[Lint.Rule.ID]` → `Set<Lint.Rule.ID>`.
The companion `effectiveDisabledRuleIDs()` already returns
`Set<Lint.Rule.ID>` for O(1) lookup; making the stored property a Set
eliminates the per-call array→set conversion and aligns storage with
query.

**Recommendation**: **Shape B**. The maximal-reuse lens cited
`Set<Lint.Rule.ID>` as the canonical example in the HANDOFF; the
existing `effectiveDisabledRuleIDs()` Set return confirms Set is the
right shape for the lookup semantic. Adopting Set at the storage layer
is the coherent typed-primitive step.

**Cascade scope**: `init(disabledRuleIDs:)` argument label, public
read-access at consumer sites. Run `grep -rln "disabledRuleIDs" $(workspace)/`
for full enumeration; preliminary scope is swift-linter + the four
rule packs + Tests; no external-org-mirror consumers identified.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 2 — `Lint.Configuration.effectiveRules()` at `Sources/Linter Primitives/Lint.Configuration.swift:125`

**Current shape**: `public func effectiveRules() -> [Lint.Rule.Configuration]`
**Compound rule**: [API-NAME-002] (compound — "effective" + "Rules")

**Proposed shape A (rename only)**: `public func resolved() -> [Lint.Rule.Configuration]`
— single-word leaf; semantically captures "rules after parent-chain
walk and disabled-filter applied." Conflicts: none (no other
`resolved` on `Lint.Configuration`).

**Proposed shape B (nested accessor)**: `public var effective: Effective`
where `Effective` exposes `.rules` and `.disabled` — Property.View
multi-form per [API-NAME-008]. Call sites become
`config.effective.rules` / `config.effective.disabled`. Pairs with
Row 3 (same multi-form).

**Recommendation**: **Shape B** — `effective.rules` + `effective.disabled`
together form a coherent two-method namespace per [API-NAME-008]
multi-form criterion. Single-method namespaces are anti-pattern per
[API-NAME-001a]; the multi-form here is genuine.

**Cascade scope**: `effectiveRules()` callers in swift-linter
(`Lint.Driver`, `Lint.Run`) — grep first. Tests update too.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 3 — `Lint.Configuration.effectiveDisabledRuleIDs()` at `Sources/Linter Primitives/Lint.Configuration.swift:149`

**Current shape**: `public func effectiveDisabledRuleIDs() -> Set<Lint.Rule.ID>`
**Compound rule**: [API-NAME-002] (compound — "effective" + "Disabled" + "RuleIDs")

**Proposed shape A (rename only)**: `public func resolvedDisabled() -> Set<Lint.Rule.ID>`
— still compound. Or `public func disabled() -> Set<Lint.Rule.ID>` —
collides with the proposed Row 1 stored property `disabled`.

**Proposed shape B (nested accessor)**: `config.effective.disabled` —
paired with `effective.rules` from Row 2. Returns `Set<Lint.Rule.ID>`.
Single-word leaf `disabled` on the `Effective` view type.

**Recommendation**: **Shape B** — same rationale as Row 2. The
`effective` accessor returns a view type whose `.rules` and
`.disabled` are the two resolved-set accessors.

**Cascade scope**: same as Row 2 (`effectiveDisabledRuleIDs()` is
called only by `effectiveRules()`; both move together).

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 4 — `Lint.Rule.withDefaultSeverity(_:)` at `Sources/Linter Primitives/Lint.Rule.Composition.swift:45`

**Current shape**: `public func withDefaultSeverity(_ severity: Diagnostic.Severity) -> Lint.Rule`
**Compound rule**: [API-NAME-002] (compound — "with" + "Default" + "Severity")

**Proposed shape A (rename only)**: `public func with(defaultSeverity severity: Diagnostic.Severity) -> Lint.Rule`
— labeled method per [API-NAME-008] single-form. `defaultSeverity`
argument label is still compound; could be `with(default:)` if the
context is clear.

**Proposed shape B (Property.View)**: not applicable — single-form
operation per [API-NAME-008]; multi-form would require sibling
combinators (e.g., `with.findings`, `with.id`) which don't currently
exist on `Lint.Rule.Composition`.

**Recommendation**: **Shape A** with argument label `with(default:)`
— "default" is the relevant qualifier; the parameter type
`Diagnostic.Severity` says the rest. Reads as
`rule.with(default: .error)`. Note: the `with*` prefix on the
*method name* is stdlib idiom for scoped-resource patterns
(`withUnsafePointer`); here we keep the `with` prefix because Swift
labeled-method idiom permits it at the *argument* label position
(per [API-IMPL-013] secondary-closure-label conventions, the same
applies to value-shaped parameters).

**Cascade scope**: combinator method — consumers chain it. Run `grep
-rln "withDefaultSeverity"` for enumeration.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 5 — `Lint.Rule.pinnedToSeverity(_:)` at `Sources/Linter Primitives/Lint.Rule.Composition.swift:58`

**Current shape**: `public func pinnedToSeverity(_ severity: Diagnostic.Severity) -> Lint.Rule`
**Compound rule**: [API-NAME-002] (compound — "pinned" + "To" + "Severity")

**Proposed shape A (rename only)**: `public func pinned(to severity: Diagnostic.Severity) -> Lint.Rule`
— labeled-method single-form per [API-NAME-008]. Reads as
`rule.pinned(to: .error)`. `pinned` is a single-word verb past
participle; `to:` is the canonical destination preposition argument
label.

**Proposed shape B**: not applicable.

**Recommendation**: **Shape A**. Pair with Row 4's argument-label
shape for sibling-shape consistency on `Lint.Rule.Composition`.

**Cascade scope**: combinator method — `grep -rln "pinnedToSeverity"`.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 6 — `Lint.Rule.defaultSeverity` at `Sources/Linter Primitives/Lint.Rule.swift:63`

**Current shape**: `public let defaultSeverity: Diagnostic.Severity`
**Compound rule**: [API-NAME-002] (compound — "default" + "Severity")

**Proposed shape A (rename only)**: `public let severity: Diagnostic.Severity`
— drops "default" prefix; the property's role is "this rule's
default severity." Risk: ambiguity — engine resolves severity at
runtime via `configuration.severity ?? rule.defaultSeverity`; dropping
"default" loses the distinction between "the static default" and
"the resolved runtime severity."

**Proposed shape B (amendment-citing)**: keep the name; cite
[API-NAME-002] amendment proposal to allow `default` as a recognized
prefix marker (analog to boolean-prefix exemption). Per the
foundation-up triage's DEFER-FOR-CONSISTENCY classification, the
`default*` prefix is load-bearing.

**Recommendation**: **DEFER** as ACCEPTABLE-as-is pending [API-NAME-002]
amendment thread. The foundation-up dogfeed triage explicitly marked
this as DEFER-FOR-CONSISTENCY ("Rename loses precision. Consider
amendment to allow `default` as a prefix marker"). Renaming to bare
`severity` invites every consumer to mistake "default" for "current"
at the call site.

**Cascade scope**: `grep -rln "defaultSeverity"` — load-bearing
across the engine.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

## swift-linter — compound identifiers (15 rows)

### Row 7 — `Lint.Driver.dispatchNestedIfPresent(...)` at `Sources/Linter Core/Lint.Driver.swift:105`

**Current shape**: `public static func dispatchNestedIfPresent(...)`
**Compound rule**: [API-NAME-002] (compound — "dispatch" + "Nested" + "If" + "Present")

**Proposed shape A (rename only)**: `public static func dispatch.nested(...)`
returning `Optional<...>` — the `ifPresent` semantic moves into the
return type (Optional means "if present" implicitly). Property.View
form; `dispatch` is a namespace on `Lint.Driver` with sibling
accessors (Row 7, 9, etc.) if multi-form materializes.

**Proposed shape B**: not applicable — no typed-primitive substitution.

**Recommendation**: **Shape A** — the `ifPresent` suffix is redundant
when the return is Optional (consumers see `.dispatch.nested(...)?`
or `if let result = .dispatch.nested(...)` — the optional shape IS
the if-present semantic).

**Cascade scope**: `grep -rln "dispatchNestedIfPresent"` — likely
single call site in `Lint.run` / CLI.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 8 — `Lint.Driver.lintSwiftPath(at:)` at `Sources/Linter Core/Lint.Driver.swift:133`

**Current shape**: `public static func lintSwiftPath(at consumerPackageRoot: File.Path) -> File.Path?`
**Compound rule**: [API-NAME-002] (compound — "lint" + "Swift" + "Path")

**Proposed shape A (rename only)**: `public static func manifest.path(at:)` (Property.View nested accessor)
— "manifest" describes what the file is (the `Lint.swift` manifest);
"path" is single-word. Sibling accessors might be `manifest.exists(at:)`,
`manifest.read(at:)`. Multi-form per [API-NAME-008].

**Proposed shape B**: not applicable — return is already typed
`File.Path?`.

**Recommendation**: **Shape A** — `manifest.path(at:)` aligns with
the [API-NAME-002] nested-accessor rule and reads cleanly at call
sites (`Lint.Driver.manifest.path(at: root)`).

**Cascade scope**: likely 2-3 call sites in `Lint.SingleFile` /
`Linter CLI`.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 9 — `Lint.Driver.resolveConfiguration(...)` at `Sources/Linter Core/Lint.Driver.swift:189`

**Current shape**: `public static func resolveConfiguration(...) throws(Paths.Path.Error) -> Lint.Configuration`
**Compound rule**: [API-NAME-002] (compound — "resolve" + "Configuration")

**Proposed shape A (rename only)**: `public static func resolve.configuration(...)` (Property.View nested accessor)
— pairs with Row 7's `dispatch.*` namespace. Multi-form if
`resolve.manifest`, `resolve.dependencies` (Row 12) also exist.

**Alternative shape A'**: `public static func configuration(at:)` —
the "resolve" verb collapses into the noun; reads as "the configuration
at this root." Single-form labeled method per [API-NAME-008].

**Proposed shape B**: not applicable — return is already typed
`Lint.Configuration`.

**Recommendation**: **Shape A'** (single-form `configuration(at:)`)
unless Row 12 (`extractDependencies`) also adopts a `resolve.*`
namespace — then **Shape A** (multi-form). The decision depends on
principal preference for the Driver's API shape.

**Cascade scope**: called from `Lint.Run`, CLI, tests. `grep -rln "resolveConfiguration"`.

**Disposition**: ☐ Shape A  ☐ Shape A'  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 10 — `Lint.Manifest.Configuration.enabledRuleIDs` at `Sources/Linter Core/Lint.Manifest.swift:74`

**Current shape**: `public let enabledRuleIDs: [Lint.Rule.ID]`
**Compound rule**: [API-NAME-002] (compound — "enabled" + "Rule" + "IDs")

**Proposed shape A (rename only)**: `public let enabled: [Lint.Rule.ID]`
— per [API-NAME-013] / [API-NAME-002] namespace-implicit-prefix
sub-rule. The struct-field-application extension (2026-05-08) is
explicit: `Lint.Manifest.Configuration.enabledRuleIDs` already
documented as a target case.

**Proposed shape B (rename + collection change)**: `public let enabled: Set<Lint.Rule.ID>`
— same rename + array→set as Row 1's Shape B. Justification:
membership-test semantic (caller asks "is this rule enabled?") is
O(1) on Set, O(N) on Array.

**Recommendation**: **Shape B** — pairs with Row 1 (`disabled`) for
sibling-shape consistency on the `enabled`/`disabled` filter pair.

**Cascade scope**: manifest decode/encode paths + `init` argument
label.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 11 — `Lint.Manifest.Configuration.disabledRuleIDs` at `Sources/Linter Core/Lint.Manifest.swift:75`

**Current shape**: `public let disabledRuleIDs: [Lint.Rule.ID]`
**Compound rule**: [API-NAME-002] (same)

**Proposed shape A/B**: same as Row 10 — rename to `disabled`
(possibly + Set). Pairs with Row 1 (the linter-primitives `Lint.Configuration.disabledRuleIDs`).

**Recommendation**: **Shape B** alongside Row 10.

**Cascade scope**: same as Row 10.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 12 — `Lint.Manifest.Configuration.excludedPaths` at `Sources/Linter Core/Lint.Manifest.swift:76`

**Current shape**: `public let excludedPaths: [File.Path]`
**Compound rule**: [API-NAME-002] (compound — "excluded" + "Paths")

**Proposed shape A (rename only)**: `public let excluded: [File.Path]`
— namespace-implicit-prefix sub-rule; type `[File.Path]` says "paths."
Sibling to Rows 10/11.

**Proposed shape B (typed primitive promotion)**: `public let excluded: [Glob.Pattern]`
— if exclusions are glob patterns (current shape's downstream semantic),
adopt the `Glob.Pattern` typed primitive at this layer. Cascade: the
F-A3.3 precedent (per the maximal-reuse memory and audit doc) already
adopted `[Glob.Pattern]` for `File.Directory.glob.files(include:)` —
the same primitive could promote `[File.Path]` here if the manifest
exclusion semantic is glob-shaped.

**Recommendation**: **Shape B IF** the manifest exclusion semantic
is glob-shaped (verify against current `Lint.Configuration.excluded:
[Lint.Filter.Prefix]` semantic — they may differ). If exclusions are
exact paths, Shape A. Principal verifies.

**Cascade scope**: manifest decode/encode + the consumer that maps
manifest excluded → engine excluded.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 13 — `Lint.Run.runCapturingSuppressed(...)` at `Sources/Linter Core/Lint.Run.swift:127`

**Current shape**: `public static func runCapturingSuppressed(...)`
**Compound rule**: [API-NAME-002] (compound — "run" + "Capturing" + "Suppressed")

**Proposed shape A (rename only)**: `public static func run(capturing: CaptureMode)`
where `CaptureMode` is an enum `.suppressed`, `.findings`, `.all`.
Single-form labeled method per [API-NAME-008]; the capture-mode
selection moves to enum case.

**Alternative shape A'**: `public static func run.captured.suppressed(...)`
(Property.View triple-nest) — heavy ceremony; rejected unless
sibling captures materialize.

**Proposed shape B**: not applicable directly — adopting an enum
for capture mode is the Shape A formulation.

**Recommendation**: **Shape A** — `run(capturing: .suppressed)` reads
cleanly and supports future capture modes without API breaks.

**Cascade scope**: `runCapturingSuppressed` called from tests + the
engine's `--capture` flag path.

**Disposition**: ☐ Shape A  ☐ Shape A'  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 14 — `Lint.SingleFile.Extractor.extractDependencies(...)` at `Sources/Linter Core/Lint.SingleFile.Extractor.swift:50`

**Current shape**: `public static func extractDependencies(from source: Swift.String) -> [SingleFile.PackageDependency]`
**Compound rule**: [API-NAME-002] (compound — "extract" + "Dependencies")

**Proposed shape A (rename only)**: `public static func dependencies(from:)`
— drops the redundant "extract" prefix (the type is `Extractor`;
extract is implicit). Single-word leaf.

**Proposed shape B**: not applicable directly.

**Recommendation**: **Shape A** — pure namespace-implicit-prefix
drop. Pairs with the proposed `PackageDependency` → `Package.Dependency`
type-name change (Row 23).

**Cascade scope**: limited — called from `Lint.SingleFile.dispatch`
path.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 15 — `Lint.SingleFile.toolsVersionMagicComment` at `Sources/Linter Core/Lint.SingleFile.swift:69`

**Current shape**: `public static let toolsVersionMagicComment: Swift.String = "swift-linter-tools-version:"`
**Compound rule**: [API-NAME-002] (compound — "tools" + "Version" + "Magic" + "Comment")

**Proposed shape A (rename only)**: `public static let header: Swift.String = "..."`
— single-word leaf; "header" semantically captures the magic-comment
file header. Loses the "tools-version" specificity at the property
name level — consumer must check inline docs.

**Alternative shape A'**: nested as `Lint.SingleFile.tools.version.marker`
(Property.View triple-nest) — heavier than the value warrants.

**Proposed shape B (typed primitive)**: introduce
`Lint.SingleFile.Header` newtype (`Tagged<Lint.SingleFile.Header, Swift.String>`)
and expose as `Lint.SingleFile.Header.canonical` — overkill for a
single magic comment.

**Recommendation**: **Shape A** (`Lint.SingleFile.header`) — the
property's existence at file-header position is informative enough;
the string value documents its own format.

**Cascade scope**: minimal — used in `Lint.SingleFile` discovery path
and tests.

**Disposition**: ☐ Shape A  ☐ Shape A'  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 16 — `Lint.SingleFile.parentConfiguration(...)` at `Sources/Linter Core/Lint.SingleFile.swift:394`

**Current shape**: `public static func parentConfiguration(...) throws(...) -> Lint.Configuration?`
**Compound rule**: [API-NAME-002] (compound — "parent" + "Configuration")

**Proposed shape A (rename only)**: `public static func parent.configuration(...)` (Property.View)
— `parent` namespace; multi-form if sibling accessors materialize.

**Alternative shape A'**: drop the "parent" prefix entirely:
`public static func configuration(parentOf:)` — single-form. Reads
as "the configuration parent of this root."

**Proposed shape B**: not applicable directly.

**Recommendation**: **Shape A'** (`configuration(parentOf:)`) —
moves the "parent" semantic to the argument label, where it reads
naturally. Pairs with Row 9's `resolveConfiguration` rename
(`Lint.Driver.configuration(at:)`).

**Cascade scope**: called from `Lint.Driver.resolveConfiguration`
chain.

**Disposition**: ☐ Shape A  ☐ Shape A'  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 17 — `Lint.Source.Walker.includePatterns` at `Sources/Linter Core/Lint.Source.Walker.swift:32`

**Current shape**: `public static let includePatterns: [Glob.Pattern] = [...]`
**Compound rule**: [API-NAME-002] (compound — "include" + "Patterns")

**Proposed shape A (rename only)**: `public static let included: [Glob.Pattern]`
— namespace-implicit-prefix sub-rule; `[Glob.Pattern]` type says
"patterns." Sibling-pair with Row 18.

**Proposed shape B**: already adopts `[Glob.Pattern]` typed primitive
(maximal-reuse lens satisfied). No further typed-primitive step
available.

**Recommendation**: **Shape A** — clean drop of redundant prefix;
sibling-shape parity with `excluded` (Row 18).

**Cascade scope**: used in `Walker.swiftSourcePaths(under:)`; minimal.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 18 — `Lint.Source.Walker.excludePatterns` at `Sources/Linter Core/Lint.Source.Walker.swift:40`

**Current shape**: `public static let excludePatterns: [Glob.Pattern] = [...]`
**Compound rule**: [API-NAME-002] (compound — "exclude" + "Patterns")

**Proposed shape A (rename only)**: `public static let excluded: [Glob.Pattern]`
— same rationale as Row 17. Sibling-shape parity.

**Recommendation**: **Shape A** alongside Row 17.

**Cascade scope**: same as Row 17.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 19 — `Lint.Source.Walker.swiftSourcePaths(under:)` at `Sources/Linter Core/Lint.Source.Walker.swift:63`

**Current shape**: `public static func swiftSourcePaths(under root: File.Path) -> [Lint.Source.Path]`
**Compound rule**: [API-NAME-002] (compound — "swift" + "Source" + "Paths")

**Proposed shape A (rename only)**: `public static func paths(under:)`
— drops "swiftSource"; the return type `[Lint.Source.Path]` already
says "source paths," and the enclosing namespace `Lint.Source.Walker`
says "Lint.Source." So the return-type vocabulary makes the bare
`paths` leaf unambiguous.

**Proposed shape B**: already adopts `Lint.Source.Path` and `File.Path`
typed primitives. No further typed-primitive step.

**Recommendation**: **Shape A** — `paths(under:)` reads as
`Lint.Source.Walker.paths(under: root)` — clear and minimal.

**Cascade scope**: 2-3 call sites in `Lint.Run` + tests.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 20 — `Lint.Suppression.Entry.ruleID` at `Sources/Linter Core/Lint.Suppression.swift:65`

**Current shape**: `public let ruleID: Lint.Rule.ID`
**Compound rule**: [API-NAME-002] (compound — "rule" + "ID")

**Proposed shape A (rename only)**: `public let rule: Lint.Rule.ID`
— drops the "ID" suffix; the type `Lint.Rule.ID` (a Tagged primitive)
already says "rule ID."

**Proposed shape B**: already adopts `Lint.Rule.ID` typed primitive.
No further typed-primitive step.

**Recommendation**: **Shape A** — clean drop. Pairs with Row 21
(parameter label rename).

**Cascade scope**: `entriesSuppressing(line:ruleID:)` parameter label
(Row 21) + tests.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 21 — `Lint.Suppression.entriesSuppressing(line:ruleID:)` at `Sources/Linter Core/Lint.Suppression.swift:99`

**Current shape**: `public func entriesSuppressing(line: Swift.Int, ruleID: Lint.Rule.ID) -> [Entry]`
**Compound rule**: [API-NAME-002] (compound — "entries" + "Suppressing")

**Proposed shape A (rename only)**: `public func entries(suppressing line: Swift.Int, rule: Lint.Rule.ID) -> [Entry]`
— single-form labeled method per [API-NAME-008]. Both labels updated
(`suppressing` describes the operation; `rule` is the Row 20 rename).

**Proposed shape B (typed primitive promotion)**: change `line: Swift.Int`
→ `line: Source.Location.Line` or similar typed primitive. The
`Swift.Int` is a raw line-number; the ecosystem has line-number
typed primitives in source-location packages. Adopting the typed
primitive matches the maximal-reuse lens.

**Recommendation**: **Shape B** — both rename AND adopt
`Source.Location.Line` (or the canonical line-number primitive).
The `Swift.Int line` is the kind of raw-Int site the maximal-reuse
memory specifically targets.

**Cascade scope**: callers of `entriesSuppressing` + tests; the
typed-primitive adoption cascades to whichever upstream layer
produces the line number.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

## swift-linter — compound type names (3 rows)

### Row 22 — `Lint.Run.ExitPolicy` at `Sources/Linter Core/Lint.Run.ExitPolicy.swift:23`

**Current shape**: `public enum ExitPolicy: Swift.String, Sendable, Hashable, CaseIterable {...}`
**Compound rule**: [API-NAME-001] (compound type name — "Exit" + "Policy")

**Proposed shape A (nested rename)**: `Lint.Run.Exit.Policy` —
introduce `Lint.Run.Exit` namespace; nest `Policy` under it. Sibling
types might be `Exit.Code`, `Exit.Reason` if they materialize.

**Proposed shape B**: not applicable — pure structural rename.

**Recommendation**: **Shape A** — per institute Nest.Name pattern.
Per [API-NAME-001a] single-type-no-namespace, `Exit` should genuinely
have multiple inhabitants OR Policy should nest under a meaningful
parent. Suggestion: `Lint.Run.Policy` (single-word at the Lint.Run
level) if no sibling types planned.

**Alternative shape A'**: `Lint.Run.Policy` — drop the "Exit"
qualifier; the namespace `Lint.Run` says "this is the run domain"
and Policy is the only policy-shaped type there.

**Recommendation**: **Shape A'** — single-word `Policy` under
`Lint.Run` is cleanest. The "exit" semantic is implicit in
`Lint.Run` (a policy for what the run does on completion).

**Cascade scope**: callers of `ExitPolicy` enum across CLI + tests.

**Disposition**: ☐ Shape A  ☐ Shape A'  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 23 — `Lint.SingleFile.PackageDependency` at `Sources/Linter Core/Lint.SingleFile.PackageDependency.swift:27`

**Current shape**: `public struct PackageDependency: Swift.Sendable, Swift.Hashable {...}`
**Compound rule**: [API-NAME-001] (compound type name — "Package" + "Dependency")

**Proposed shape A (nested rename)**: `Lint.SingleFile.Package.Dependency`
— introduce `Lint.SingleFile.Package` namespace; nest `Dependency`
under it. Sibling types might be `Package.Manifest`, `Package.Product`,
`Package.Path` if they materialize — and they DO exist conceptually
(consumer code references SwiftPM packages elsewhere). Genuine
namespace candidate.

**Proposed shape B**: not applicable.

**Recommendation**: **Shape A** — Package as a sub-namespace is the
canonical SwiftPM-domain nesting. Pairs with the SwiftPM ecosystem's
own `Package.Description`, `Package.Dependency` etc.

**Cascade scope**: declared product type — every reference to
`Lint.SingleFile.PackageDependency` changes. `grep -rln "PackageDependency"`.

**Disposition**: ☐ Shape A  ☐ Shape B  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

### Row 24 — `Lint.SingleFile` at `Sources/Linter Core/Lint.SingleFile.swift:59`

**Current shape**: `public enum SingleFile: Swift.Sendable {}`
**Compound rule**: [API-NAME-001] (compound type name — "Single" + "File")

**Proposed shape A (nested rename)**: `Lint.Single.File` — introduce
`Lint.Single` namespace; nest `File` under it. Sibling types under
`Lint.Single` would be unclear (single what?).

**Alternative shape A'**: rename to a non-compound single concept:
`Lint.Manifest` (already exists!) — collision. Or `Lint.Source`
(also exists). Or `Lint.Inline` — semantically unclear. Or
`Lint.Standalone` — single-word; describes "a single-file consumer
shape" (Shape γ in the docs).

**Proposed shape B (massive cascade)**: This is the *primary
consumer-discovery shape* in swift-linter — every Lint.SingleFile.*
reference cascades. Hundreds of sites across engine + tests + reporter.

**Recommendation**: **DEFER** — the cascade scope is too large for
Phase 3 alongside the other 23 rows. Worth its own follow-up thread.
The institute's `Nest.Name` rule clearly applies; the question is
**when** to bear the cascade cost.

**Cascade scope**: ~200+ sites in `Lint.SingleFile.{Materializer,
Extractor, PackageDependency, Error, Source}` — every nested type
moves under the new namespace.

**Disposition**: ☐ Shape A  ☐ Shape A'  ☐ DEFER  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

## Supplemental — rule-pack public DSL carry-forward

### Row 25 — `Lint.Rule.Bundle.brandOwner` at `swift-primitives-linter-rules/Sources/Linter Primitives Rules/Lint.Rule.Bundle.brandOwner.swift:52`

**Current shape**: `public static let brandOwner: [Lint.Rule.Configuration] = { ... }()`
**Compound rule**: [API-NAME-002] (compound — "brand" + "Owner")

**Scope note**: Phase 2 declared scope was swift-linter +
swift-linter-primitives. This row is on swift-primitives-linter-rules
(rule-pack, public DSL). Listed for principal awareness — surfaced
by Phase 1 ambiguity (rule-pack public API).

**Proposed shape A (rename only)**: `public static let brand: [Lint.Rule.Configuration]`
— single-word leaf; the bundle's documented purpose is "brand-owner
primitives-tier bundle." `brand` captures the brand-owning aspect.

**Alternative shape A'**: `Lint.Rule.Bundle.brand.owned` (Property.View) — but `Lint.Rule.Bundle.brand` alone is a single accessor on `brand` namespace, fires [API-NAME-001a] single-type-no-namespace. Multi-form needs sibling accessors (`brand.universal`, `brand.institute`, etc.) which aren't part of the design.

**Proposed shape B**: not applicable.

**Recommendation**: **Shape A** — `Lint.Rule.Bundle.brand` is a
clean single-word renaming. Pairs with the existing bundle accessors
`Lint.Rule.Bundle.universal`, `Lint.Rule.Bundle.institute`,
`Lint.Rule.Bundle.primitives` — all single-word leaves.

**Cascade scope**: consumer brand-owner packages
(swift-ordinal-primitives, swift-cardinal-primitives,
swift-affine-primitives per the doc comment) — 3+ consumers + tests.
Workspace-wide grep per [HANDOFF-050] required.

**Disposition**: ☐ Include in Phase 3  ☐ Defer to separate thread  ☐ ACCEPTABLE-as-is
**Rationale**: ___________

---

## Phase 2 halt report summary

**Catalog totals**:

| Category | Count |
|----------|---:|
| Rows with Shape A recommended | 14 (rows 4, 5, 7, 8, 14, 15, 17, 18, 19, 20, 23, 25 + 2 A') |
| Rows with Shape B recommended (typed-primitive adoption) | 5 (rows 1, 10, 11, 12*, 21) |
| Rows with multi-form Property.View recommended | 2 (rows 2, 3 — `effective.{rules,disabled}`) |
| Rows recommended DEFER | 2 (rows 6 — `defaultSeverity` precision; row 24 — `Lint.SingleFile` cascade) |
| Rows requiring principal verification before disposition | 1 (row 12 — Glob semantic) |

\* Row 12 Shape B is conditional on principal verifying Glob semantic.

**Cascade flags ([HANDOFF-050] workspace-wide grep required at Phase 3 dispatch)**:

- Row 1 / 10 / 11 (`disabledRuleIDs`, `enabledRuleIDs`) — load-bearing
  across engine + 4 rule packs + manifest decode paths.
- Row 6 (`defaultSeverity`) — load-bearing across the engine; DEFER
  recommended pending [API-NAME-002] amendment.
- Row 22-24 (compound type names — `ExitPolicy`, `PackageDependency`,
  `SingleFile`) — type renames cascade to every reference. Row 24 in
  particular cascades to ~200+ sites.
- Row 25 (`brandOwner`) — cascades to 3+ brand-owner primitive packages
  (swift-ordinal-primitives, swift-cardinal-primitives,
  swift-affine-primitives) per its doc comment.

**Scope ambiguities (re-stated)**:

- 33 internal swift-linter compound-identifier findings — NOT in
  Phase 2 catalog scope. Recommendation: extend Phase 1 mechanical
  (visibility-shift) on principal authorization.
- 5 internal swift-linter compound-type-name findings (`Linter CLI`
  type name + test fixtures) — NOT in Phase 2 catalog. Some are
  product-binding (`Linter CLI` is the executableTarget name), some
  are test fixtures legitimately compound. Treatment: separate Thread F.

**Pre-Phase-3 verification checklist** (when principal authorizes):

- [ ] For each Shape B disposition, run workspace-wide grep
      ([HANDOFF-040] both literal AND generic-instantiated forms)
      before scope-locking.
- [ ] For Row 12 (Glob semantic), verify the manifest's `excludedPaths`
      semantic (exact path match vs glob match) before choosing
      Shape A vs B.
- [ ] For Row 24 (`Lint.SingleFile`), if accepted, plan a dedicated
      dispatch (cascade scope ~200+ sites).
- [ ] Each Shape B rename's commit MUST include both the rename AND
      the typed-primitive adoption as one coherent change per
      HANDOFF Phase 3 requirement.

---

## Awaiting principal disposition

Phase 3 (execute signed-off renames) and Phase 4 (verification +
closure) do NOT begin until the principal dispositions each row
above. Per HANDOFF:

> Phase 2 HALT: subordinate commits the catalog draft (no code edits
> yet), pushes to origin/main, and HALTS for principal sign-off.

Catalog file: this document.
Catalog commit: pending principal review.
