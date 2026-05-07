# swift-linter

SwiftSyntax-based AST linter for the Swift Institute ecosystem. Augments
[SwiftLint](https://github.com/realm/SwiftLint) by hosting AST-shaped rules
whose predicates cannot be expressed as a regex on source text — typed-
system escape patterns, ownership-discipline violations, and ecosystem-
specific idioms.

## Install

```swift
.package(url: "https://github.com/swift-foundations/swift-linter", from: "1.0.0"),
```

The executable ships in the `Linter CLI` product; for ad-hoc invocation,
`swift run --package-path <this-package> swift-linter <target>` works out
of the box.

## Quickstart (zero-config)

```bash
swift run swift-linter /path/to/your-package
```

With no `Lint.swift` at the target's package root, every built-in rule
activates at default severity. Output is SwiftLint-compatible textual
lines by default; `--format sarif` emits SARIF 2.1.0 JSON suitable for CI
artifact upload.

## Customization via Lint.swift

Drop a typed-Swift-DSL configuration at your package root (mirroring
`Package.swift`'s manifest pattern):

```swift
// Lint.swift
import Linter

let manifest = Lint.Manifest(
    enabledRuleIDs: [
        "unchecked_call_site",          // R5
        "cardinal_count_minus_one",     // R1
    ],
    disabledRuleIDs: [
        "chained_rawvalue_access",      // R3 — opted out
    ],
    excludedPaths: [
        try File.Path("Tests/Fixtures"),
        try File.Path(".build"),
    ]
)
```

The linter compiles `Lint.swift` via `swift-manifest`, captures the typed
value as JSON, and reconstructs a runtime `Lint.Configuration`.

## Two consumer shapes

`swift-linter` detects two configurations at the consumer's package root:

1. **`Lint/` nested SwiftPM package** (recommended) — a SwiftPM package
   directory alongside `Package.swift` that imports rule packages and
   declares activation via a typed `Lint.Manifest`. Supports arbitrary
   rule packs (third-party or in-house) and custom rules with their own
   dependencies.

2. **Single-file `Lint.swift`** (sugar form) — a terse declaration at
   the package root, no nested package required. Activates zero rules
   until a default rule-pack convention ships; consumers who need rules
   to fire today MUST adopt the `Lint/` nested-package shape.

The `Lint/` shape is the canonical form going forward; single-file
`Lint.swift` is preserved as a future-facing sugar form for consumers
that adopt the canonical rule set without per-package customization.

## Inheritance via `// parent:` directive

Layer your manifest on top of a canonical configuration hosted at a URL.
Place the directive in the first 30 lines of `Lint.swift`:

```swift
// parent: https://raw.githubusercontent.com/your-org/.github/main/Lint.swift
import Linter

let manifest = Lint.Manifest(enabledRuleIDs: [])  // inherit all from parent
```

Schemes accepted: `http://`, `https://`, `file://`. The driver fetches each
parent via `curl` (memoized per process), with cycle detection and a
depth-16 backstop. On any fetch failure the driver warns and falls back to
the consumer-only configuration — the chain is best-effort. A child's
`disabledRuleIDs` overrides a parent's `enabledRuleIDs` for the same rule
via per-TYPE "later layer wins" semantics.

## Adoption by third-party teams

Host your team's canonical `Lint.swift` at `<your-org>/.github/Lint.swift`;
the raw GitHub URL is the conventional public pointer. Per-package
consumers then declare:

```swift
// parent: https://raw.githubusercontent.com/<your-org>/.github/main/Lint.swift
import Linter

let manifest = Lint.Manifest(enabledRuleIDs: [/* per-package overrides */])
```

This mirrors the Tier 1 / Tier 2 / consumer pattern used by
`swift-primitives` (which inherits from `swift-institute`); each layer
contributes the rules that apply at its scope.

## Documentation

A DocC catalog covering the rule catalog, configuration schema, and CI
integration recipes is deferred to a separate cycle. For a worked example
of the file-based canonical pattern in production, see
`swift-primitives/swift-tagged-primitives`'s `Lint.swift`.
