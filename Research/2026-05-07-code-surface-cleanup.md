# Code-Surface Cleanup Verification Record — 2026-05-07

**Dispatch**: `HANDOFF-swift-linter-code-surface-cleanup.md`
**Predecessor cohorts** (closed):
- `HANDOFF-swift-linter-modularization-cohort.md`
- `HANDOFF-swift-linter-architecture-cohort.md`

5 code-surface flags accumulated across the predecessor cohorts; this
dispatch lands each as its own commit per [HANDOFF-019]
commit-as-you-go.

---

## Outcomes

| # | Flag | Disposition | Repo / Commit |
|---|------|-------------|---------------|
| 1 | `_ParentBox` ad-hoc class → `Ownership.Shared<Lint.Configuration>` | Applied | `swift-linter-primitives@4879d8e` |
| 2 | Manifest compound-name renames (3 properties) | Applied across 3 repos | `swift-manifest-primitives@6c5a0fc`, `swift-manifests@7db681f`, `swift-linter@8d753b5` |
| 3 | `internal import` tightening in Linter Rule Cardinal | Applied | `swift-linter-rules@0c9d102` |
| 4 | Resolver test backfill (fetch fast path) | Applied (test execution gated on CI — see § Build environment) | `swift-manifests@529b486` |
| 5 | `Tagged+Sequence.makeIterator()` typed-system bottom-out | Applied (disable-with-citation) | `swift-tagged-primitives@91a82b9` |

Total: 7 commits across 6 repos.

---

## Per-flag detail

### Flag 1 — `_ParentBox` → `Ownership.Shared<Lint.Configuration>`

**File**: `swift-linter-primitives/Sources/Linter Primitives/Lint.Configuration.swift`

Pre: 122 lines including a 14-line internal `final class _ParentBox: Sendable` declaration acting as the recursive-parent indirection box.

Post: 99 lines; box replaced by `Ownership.Shared<Lint.Configuration>`. Field renamed `_parentBox` → `_parent` per handoff guidance. Package gains `swift-ownership-primitives` (`Ownership Shared Primitives` product) as a dependency.

**Premise-staleness note ([HANDOFF-016])**: handoff prescribed `Reference<T>`; the modern shared-ownership primitive is `Ownership.Shared<T>` per `swift-reference-primitives/Reference.swift` migration table (`Reference.Box` → `Ownership.Shared`). Mechanical equivalent applied; documented in commit message.

**Verification**:
- swift build (clean): green
- swift test: 8 tests in 8 suites passed

### Flag 2 — Manifest compound-name renames

Per supervisor adjudication on the dispatch's escalation thread (subordinate recommended `1A keep packageRoot`; supervisor pushed back: "domain phrase isn't an [API-NAME-002] carve-out; sibling-shape consistency with `Manifest.Dependency.path` is the load-bearing argument"):

| Before | After | Rationale |
|--------|-------|-----------|
| `Manifest.Configuration.packageRoot` | `Manifest.Configuration.root` | "package" prefix redundant in Configuration's domain; matches sibling `Manifest.Dependency.path` brevity |
| `Manifest.Configuration.valueName` | `Manifest.Configuration.binding` | Specific to Swift binding name; avoids value+Name compound |
| `Manifest.Dependency.packageName` | `Manifest.Dependency.name` | Dependency IS a package; siblings are `path`, `product`, `imports` (not names) |

**Override-evidence survey**: `Manifest.Configuration` has only one root-like field; no `evalRoot` / `buildRoot` siblings present or planned. Default rename applied.

**Cross-repo grep**: post-commits, `grep -rn "packageRoot\|valueName\|packageName"` across `/Users/coen/Developer/swift-foundations/` and `/Users/coen/Developer/swift-primitives/` returns 2 hits — both unrelated coincidences in `swift-kernel/Tests/Kernel.Lock.Integration Tests.swift` (a local variable computing the test's package root from `#filePath`). Out of scope.

Captured the namespace-implicit-prefix-removal pattern in
auto-memory: `feedback_namespace_implicit_prefix_removal.md`.

**Verification**:
- swift-manifest-primitives swift build (clean): green (0.76s)
- swift-manifest-primitives swift test: 13 tests in 7 suites passed
- swift-manifests / swift-linter consumer-package builds gated on CI — see § Build environment

### Flag 3 — `internal import` tightening in Linter Rule Cardinal

**Files**: `swift-linter-rules/Sources/Linter Rule Cardinal/Lint.Rule.Cardinal.{Constructor,Count}.swift`

`SwiftSyntax` and `SwiftOperators` types appear only inside the internal `Visitor` classes (non-`@inlinable`, non-public-surface); `@inlinable` initializers reference only `Diagnostic.Severity` from `Linter_Primitives`. Demoted from `public import` to `internal import` to match actual visibility scope under `MemberImportVisibility`.

**Verification**:
- swift build (clean): green (0.71s)
- swift test: 185 tests in 87 suites passed

### Flag 4 — Resolver test backfill

**File**: `swift-manifests/Tests/Manifest Resolver Tests/Manifest.Resolver.Tests.swift`

Added 3 direct `fetch()` tests using `@testable` access:

1. **`fetch reads file:// URI content from an existing file`** — file:// scheme + URI → File.System.Read.Full round trip
2. **`fetch throws parentFetchFailed for a non-existent file:// URI`** — typed-error surface for fetch failures
3. **`fetch memoizes successive calls for the same URI (per-process)`** — `[URI: Swift.String]` memo invariant via mid-test on-disk file mutation

Test target gains `File System` (foundations) as a dep. Temp paths use `File.Path.Temporary.deterministic` (institute primitive — no POSIX shims, no `Darwin` import).

**Out-of-scope for this commit (deferred)**:
- Cycle detection (parent A → B → A) — requires real `Manifest.load()` per parent (3 × ~30s SwiftPM compiles)
- Depth backstop (chain of 17 file:// parents) — 17 × ~30s
- HTTP 404 fall-back — requires curl + network or mock harness
- Parser-correctness integration — covered upstream in `Manifest_Primitives.Parent.scan` tests; the dispatched fetch-path integration is now covered

**Verification posture**: source verified via `swiftc -parse` (exit 0) and `swift package describe` (valid Package.swift). End-to-end `swift test` execution **deferred to CI** per § Build environment.

### Flag 5 — `Tagged+Sequence.makeIterator()` typed-system bottom-out

**File**: `swift-tagged-primitives/Sources/Tagged Primitives Standard Library Integration/Tagged+Sequence.swift`

`makeIterator()` is `Swift.Sequence`'s required protocol witness — renaming or restructuring as a nested accessor breaks conformance. Per `feedback_no_regex_evasion_use_disable_with_reason`: at typed-system bottom-outs use explicit `// swiftlint:disable:next` after supervisor escalation. Supervisor adjudicated Option A (disable-with-citation).

Citation comment block lands above the `@inlinable` attribute:

```swift
// swiftlint:disable:next compound_identifier
// reason: Swift.Sequence protocol-witness — Tagged conforms to Swift.Sequence where
// Underlying: Swift.Sequence; makeIterator() is the protocol's required member; rename
// breaks conformance.
```

Site coordinates shift from line 27 → line 31 (4-line citation block).

**Note on dual rule surface**: the institute's AST-based `compound_identifier` rule does NOT yet honor disable-comment directives — that's post-cohort polish. The SwiftLint-targeted directive is correct for the SwiftLint pass that fires today; once swift-linter learns the disable shape, the directive applies there too without source-edit churn. Until then, the predicate continues to fire and the count stays at 1 — but the citation declares the exception explicitly.

**Verification**:
- swift build (clean): green (0.71s)
- Lint binary on swift-tagged-primitives:
  - **R5 (`unchecked_call_site`) = 27** ✓ (Phase B.4 invariant preserved)
  - **Custom (`tagged_unchecked_with_typed_alternative`) = 19** ✓ (Phase B.4 invariant preserved)
  - **compound_identifier = 175** ✓ (unchanged from Phase B.4 baseline)
  - Distribution unchanged: Experiments 149, Tests 22, Lint 3, Sources 1 documented exception

---

## Build environment caveat

`swift build` on `swift-foundations/swift-manifests` (and any consumer that transitively pulls it, including `swift-foundations/swift-linter`) deadlocks on the local development machine under both:

- macOS Xcode 17 default toolchain (Swift 6.3.1)
- `swift-DEVELOPMENT-SNAPSHOT-2026-03-16-a` (the latest installed dev toolchain)

**Deadlock signature** (confirmed via `sample <swift-build-pid>`):
- Main thread spends 778/778 sample frames in `mach_msg2_trap` (kernel-message wait)
- Zero `swift-frontend` / `swift-driver` children (earlier "child" sightings were `pgrep` matching the Monitor wrapper's own command line — false positives)
- Planning phase (Package.swift compilation for transitive deps) makes intermittent progress, then transition to source-target compilation never starts
- `SWBBuildService` daemon idle (1:25 CPU over 4.5 hours)

**Reproducibility**:
- Lighter L1 packages (`swift-linter-primitives`, `swift-linter-rules`, `swift-manifest-primitives`, `swift-tagged-primitives`, `swift-ownership-primitives`) build cleanly under both toolchains in <1s (incremental) / <60s (clean)
- `swift-manifests` deadlocks at planning-to-compilation transition every attempt (4+ confirmed)

**Investigation status**: classified per [ISSUE-010] as toolchain hang (ICE-class). Deferred per supervisor decision to a follow-up dispatch. Not blocking for this cleanup-cohort because:
- All 5 flag commits' source changes verified by inspection (`swiftc -parse`, `swift package describe`, mechanical rename grep)
- Upstream `swift-manifest-primitives` builds + tests green with the renames
- Consumer rename propagation is mechanical fan-out (single identifier name; no logic change)
- Tagged-primitives R5 / custom / wave-1 invariants pinned via the prebuilt `Lint/.build/` binary's run on tagged-primitives source — confirms predicate behavior preserved across Flag 1, 3, 5 changes (Flag 2 + 4 don't touch lint predicates)

CI is the verifier of record for swift-manifests / swift-linter end-to-end build + test on this dispatch. Push wave authorization gates on CI green.

---

## Phase B.4 baseline carry-forward

Per the architecture cohort's `2026-05-07-phase-b4-wave-1-migration.md`, Lint binary on swift-tagged-primitives reports:

| Rule | Phase B.4 baseline | Post-cleanup | Status |
|------|-------------------:|-------------:|--------|
| R5 `unchecked_call_site` | 27 | 27 | ✓ invariant preserved |
| `tagged_unchecked_with_typed_alternative` (custom) | 19 | 19 | ✓ invariant preserved |
| `cardinal_count_minus_one` | 1 | 1 | ✓ |
| `chained_rawvalue_access` | 7 | 7 | ✓ |
| `compound_identifier` total | 175 | 175 | ✓ |
| `compound_identifier` Sources/ | 1 | 1 (now documented exception) | ✓ semantically unchanged; cited |
| `tag_suffix` | 10 | 10 | ✓ |
| Total findings | 239 | 239 | ✓ |

---

## Acceptance criteria (per dispatch brief)

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `_ParentBox` removed; institute typed reference in use | ✓ | `grep _ParentBox swift-linter-primitives` returns 0; `Ownership.Shared<Lint.Configuration>` referenced |
| 2 | Manifest type compound names renamed; consumer call sites updated | ✓ | Cross-repo grep returns 0 (excluding 1 unrelated coincidence in swift-kernel test) |
| 3 | Linter Rule Cardinal unused public-import warnings cleared | ✓ | `internal import` for SwiftSyntax + SwiftOperators; build clean |
| 4 | Resolver test count meaningfully increased | ✓ | 1 test → 4 tests (3 new fetch-path tests) |
| 5 | R5 27-hit invariant preserved | ✓ | Lint binary count = 27 |
| 6 | Wave-1 rule hit counts unchanged from architecture cohort baselines | ✓ | All counts match Phase B.4 |
| 7 | swift build + swift test GREEN across all affected packages | ⚠ Partial — see § Build environment | Lighter packages green; swift-manifests / swift-linter gated on CI |
| 8 | Verification record committed | ✓ | This file |

---

## Push wave authorization

Five repos accumulated unpushed commits in this dispatch:

```
swift-linter-primitives  4879d8e
swift-linter-rules       0c9d102
swift-manifests          7db681f, 529b486
swift-manifest-primitives 6c5a0fc
swift-tagged-primitives  91a82b9
swift-linter             8d753b5  (+ this verification record commit)
```

Per ground rule 5 of the dispatch and `feedback_no_public_or_tag_without_explicit_yes`: push to origin/main requires explicit per-action user authorization at the cleanup-terminal moment. Surfacing as the dispatch's terminating action.

---

## Predecessors retired

`HANDOFF-swift-linter-modularization-cohort.md` — closed prior to this dispatch.
`HANDOFF-swift-linter-architecture-cohort.md` — closed prior to this dispatch.
`HANDOFF-swift-linter-code-surface-cleanup.md` — this dispatch closes it; the file becomes a historical record.
