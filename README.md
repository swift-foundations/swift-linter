# swift-linter

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

SwiftSyntax-based AST linter for Swift packages. Hosts rules whose
predicates require an abstract syntax tree — typed-system escape
patterns, ownership-discipline violations, spec-mirror conformances —
that cannot be expressed as a regex on source text.

## Quick Start

Run the linter against any Swift package directory:

```bash
swift run swift-linter /path/to/your-package
```

The engine ships rule-pack-agnostic — without an explicit configuration,
zero rules fire. To activate a rule set, drop a `Lint/` nested SwiftPM
package at your package root (see *Adopting the `Lint/` shape* below).

Output is SwiftLint-compatible textual lines by default; `--format sarif`
emits SARIF 2.1.0 JSON suitable for CI artifact upload.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/swift-foundations/swift-linter.git", from: "0.1.0"),
]
```

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Linter", package: "swift-linter"),
    ]
)
```

The `swift-linter` executable ships as a separate product of the same
package. For ad-hoc invocation,
`swift run --package-path <this-package> swift-linter <target>` works
out of the box.

## How it relates to SwiftLint and swift-format

`swift-linter` is not a replacement for either tool; the three differ in
posture, not in capability ceiling. All three operate over Swift source
and all three reach AST-shaped rules — the question is whether the AST
path is the *primary* invocation or an opt-in mode alongside something
else.

| Tool | Posture | Primary mechanism |
|------|---------|-------------------|
| [swift-format](https://github.com/swiftlang/swift-format) | Formatter with a `lint` subcommand | SwiftSyntax-based formatting + style rules; ships ~43 rules covering indentation, brace placement, ordered members, doc-comment shape, and structural smells |
| [SwiftLint](https://github.com/realm/SwiftLint) | Style/convention linter; rules are predominantly SwiftSyntax-based, with an opt-in `analyze` command that adds SourceKit-backed type-information rules | SwiftSyntax for the common case; SourceKit-LSP via `swiftlint analyze` when type information is required |
| **swift-linter** (this package) | AST-only by construction; AST predicates ARE the surface | SwiftSyntax + SwiftParser; no SourceKit-LSP dependency in the chain |

Use all three together: `swift-format` for style normalization, SwiftLint
for the broad style/convention pack (with `swiftlint analyze` for
type-information rules), swift-linter for the cases where the rule's
identity is the AST predicate itself — typed-system escape patterns,
ownership-discipline checks, spec-mirror conformances.

## Two consumer shapes

`swift-linter` detects two configuration shapes at the consumer's
package root. **Most consumers should adopt `Lint.swift`**; `Lint/` is
the advanced shape, reserved for cases the single-file shape cannot
express.

1. **`Lint.swift` single file** (recommended for most consumers) — a
   single Swift file at the package root declaring tools-version,
   rule-pack dependencies, and the active rule set via
   `Lint.run(dependencies:) { ... }`. Covers the common case of
   activating an institute-published bundle
   (`Lint.Rule.Bundle.universal` / `.institute` / `.primitives`),
   optionally narrowed via `.excluding(rules:)` for brand-owner
   subtractions. No nested SwiftPM resolution; one file, one parse.

2. **`Lint/` nested SwiftPM package** (advanced) — a
   `Lint/Package.swift` + `Lint/Sources/Lint/main.swift` pair that
   imports rule packages and instantiates `Lint.Configuration`
   directly via the result-builder DSL. Required when the consumer
   needs in-house custom rules (arbitrary Swift code defining new
   `Lint.Rule` instances), third-party rule packs not declared in any
   institute bundle, or per-rule programmatic configuration with
   constructor calls that take consumer-side domain values.

Both shapes produce the same `Lint.Configuration` at runtime — see
[*Internal model*](#internal-model).

## Adopting `Lint.swift` (recommended)

Create a `Lint.swift` file at your package root, alongside `Package.swift`:

```
your-package/
├── Package.swift
├── Lint.swift          ← here
└── Sources/...
```

The file declares the tools-version directive, imports the rule pack(s)
the activated bundle pulls in, and calls `Lint.run(dependencies:) { ... }`
with the activated bundle in the trailing closure:

```swift
// swift-linter-tools-version: 0.1
// (Apache-2.0 license header)

import Linter
import Linter_Institute_Rules

Lint.run(dependencies: [
    .package(
        url: "https://github.com/swift-foundations/swift-institute-linter-rules.git",
        from: "0.1.0",
        products: ["Linter Institute Rules"]
    ),
]) {
    Lint.Rule.Bundle.institute
}
```

**Tools-version directive** (`// swift-linter-tools-version: 0.1`) MUST
be the first line — it informs the engine which DSL version the file
targets, mirroring SwiftPM's `swift-tools-version` discipline.

**Bundle selection**: activate the bundle matching your package's layer
in the five-layer architecture — `Lint.Rule.Bundle.universal` for
universal Swift code, `.institute` for L2/L3 standards and foundations,
`.primitives` for L1 primitives. The bundles compose additively
(`institute = universal + institute-pack`; `primitives = institute +
primitives-pack`), so activating a higher-tier bundle transitively
activates the lower tiers' rules.

**Brand-owner exclusions**: brand-owner packages (those whose primary
export is a typed primitive whose rules target external consumers'
access to the brand) narrow the bundle via `.excluding(rules:)`:

```swift
Lint.Rule.Bundle.primitives.excluding(rules: [
    Lint.Rule.`raw value access`.id,
    Lint.Rule.`unchecked call site`.id,
    // ...
])
```

Each rule referenced by `.id` requires its declaring module directly
imported under Swift 6.3+ `MemberImportVisibility` (SE-0444). Each
exclusion SHOULD carry an in-file comment naming the brand-boundary
site that justifies it.

**Invocation**: `swift run swift-linter .` from your package root.

## Adopting `Lint/` (advanced)

Adopt the nested-package shape ONLY when one of these triggers applies:

| Trigger | Why `Lint.swift` cannot express it |
|---|---|
| In-house custom rules (Swift code defining new `Lint.Rule` instances) | Custom rules need a SwiftPM compilation unit; a single-file `Lint.swift` parses but does not compile arbitrary rule code |
| Third-party rule packs not declared in any institute bundle | Activating a non-institute rule pack requires declaring it as a SwiftPM dependency and importing its module — needs `Package.swift` |
| Per-rule programmatic configuration with constructor calls | The `Lint.Configuration { Lint.Rule.Configuration.enable(...) }` DSL accepts rule constructor calls with consumer-side domain values; the bundle DSL is metatype-driven |

If none of these triggers apply, use `Lint.swift` instead.

Create a `Lint/` directory at your package root with the following layout:

```
your-package/
├── Package.swift
├── Sources/...
└── Lint/
    ├── Package.swift
    └── Sources/Lint/main.swift
```

`Lint/Package.swift` depends on the rule packs you want active:

```swift
// Lint/Package.swift
let package = Package(
    name: "Lint",
    products: [.executable(name: "Lint", targets: ["Lint"])],
    dependencies: [
        .package(url: "https://github.com/swift-foundations/swift-linter.git", from: "0.1.0"),
        .package(url: "https://github.com/swift-foundations/swift-linter-rules.git", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "Lint",
            dependencies: [
                .product(name: "Linter", package: "swift-linter"),
                .product(name: "Linter Rule Unchecked", package: "swift-linter-rules"),
                .product(name: "Linter Rule Cardinal", package: "swift-linter-rules"),
            ]
        ),
    ]
)
```

`Lint/Sources/Lint/main.swift` activates the imported rules through a
`Lint.Configuration` result-builder, then runs the linter against the
consumer's source tree:

```swift
// Lint/Sources/Lint/main.swift
import File_System
import Linter
import Linter_Reporter_Text
import Linter_Rule_Unchecked
import Linter_Rule_Cardinal
import Terminal_Primitives

let configuration = Lint.Configuration {
    Lint.Rule.Configuration.enable(Lint.Rule.Unchecked.self)
    Lint.Rule.Configuration.enable(Lint.Rule.Cardinal.Count.self)
}

let arguments = Swift.CommandLine.arguments
let pathStrings: [Swift.String] = arguments.count >= 2
    ? [Swift.String](arguments.dropFirst())
    : ["."]

do {
    let consumerPaths: [File.Path] = try pathStrings.map { try File.Path($0) }
    let findings = try Lint.Run.run(paths: consumerPaths, configuration: configuration)
    Lint.Reporter.Text.emit(findings: findings, to: Terminal.Stream.stdout.write)
} catch {
    print("[Lint] error: \(error)")
}
```

Rules are activated by metatype reference (`Lint.Rule.Unchecked.self`),
not by string identifier — the engine resolves identity through `.self`
and propagates the typed metatype through the configuration. The
result-builder's top-level position requires the fully-qualified
`Lint.Rule.Configuration.enable(...)` form (the builder declares
multiple `buildExpression` overloads, so leading-dot inference is
ambiguous in the unconstrained position; inside `if`/`for` bodies the
contextual type narrows and the leading-dot form works there).

`swift run swift-linter <package>` detects the consumer's `Lint/`
nested package, builds it, and dispatches the lint run to the
consumer's `Lint` executable, which links engine + rule packs and
runs `Lint.Run.run(paths:configuration:)` against the consumer's
source tree.

> **Wire format note**: `Lint.Manifest` exists as a separate type for
> the cross-process JSON wire format used by the single-file
> `Lint.swift` subprocess path. Nested-package consumers do not cross
> a JSON boundary — metatypes flow directly through
> `Lint.Configuration` — so the consumer surface is the typed
> result-builder above, not `Lint.Manifest`.

## Internal model

**`Lint/` is the canonical internal implementation; `Lint.swift` is
built on top of that.** The engine's mental model is the typed
`Lint.Configuration` produced by a result-builder DSL — exactly what
`Lint/Sources/Lint/main.swift` constructs explicitly. `Lint.swift` is a
single-file front-end whose source is parsed by
`Lint.File.Single.Extractor`, lifted to a `Lint.Configuration` via
`Lint.Configuration.lift`, and then executed by the same
`Lint.Run.run(paths:configuration:)` entry the nested-package shape
calls directly. From the engine's perspective, both shapes converge at
the same internal type; the consumer's choice is purely ergonomic.

The asymmetry — recommend single-file, canonicalize on nested-package —
is deliberate:

- The single-file shape minimizes consumer-side setup cost (one file,
  one parse, no nested SwiftPM resolution) for the common case of
  activating an institute bundle with optional brand-owner exclusions.
- The nested-package shape exposes the full power of the typed DSL
  (custom rule types, third-party rule packs, programmatic per-rule
  configuration) for cases the single-file cannot express.
- Internal canonicalization on nested-package keeps the engine's
  contract single-source-of-truth — every front-end produces the same
  downstream `Lint.Configuration`. A future declarative-only front-end
  (e.g., a YAML mode) would ship as a new parser producing the same
  internal type, not as a parallel execution path.

## Inheritance via `// parent:` directive

Layer your configuration on top of a canonical configuration hosted at
a URL. Place the directive in the first 30 lines of `Lint.swift` (or
`Lint/Sources/Lint/main.swift`):

```swift
// swift-linter-tools-version: 0.1
// parent: https://raw.githubusercontent.com/<your-org>/.github/main/Lint.swift

import Linter
import Linter_Institute_Rules

Lint.run(dependencies: [
    .package(
        url: "https://github.com/swift-foundations/swift-institute-linter-rules.git",
        from: "0.1.0",
        products: ["Linter Institute Rules"]
    ),
]) {
    Lint.Rule.Bundle.institute
}
```

Schemes accepted: `http://`, `https://`, `file://`. The driver fetches
each parent via `curl` (memoized per process), with cycle detection and
a depth-16 backstop. On any fetch failure the driver warns and falls
back to the consumer-only configuration — the chain is best-effort.
Per-rule overrides at any layer override deeper layers under "later
layer wins" semantics.

The conventional public pointer for an org's canonical configuration is
its `.github` repo's raw URL: `<your-org>/.github/main/Lint.swift`.
This mirrors SwiftLint's `parent_config:` cascade at the file layer.

## Architecture

### Stability and SemVer

`swift-linter` is pre-1.0. Minor-version boundaries (0.1.x → 0.2.0)
admit source-breaking changes; consumers pinning `from: "0.1.0"` should
plan to audit migration notes at each minor bump. The 1.0 inflection
will mark the API surface as stable under the standard SemVer contract
(no source-breaking changes in minor versions; deprecations precede
removals).

The known 0.1.x → 0.2 candidates are documented at the API surface
itself; the most prominent is the bare-form rename of `Lint.Manifest`
struct fields (see "Wire-key stability" below).

### Wire-key stability

`Lint.Manifest` carries three array-shaped fields —
`enabledRuleIDs`, `disabledRuleIDs`, `excludedPaths` — that the engine
serializes to JSON when crossing the consumer-driver-shim subprocess
boundary. The JSON wire-keys for these fields (`"enabledRuleIDs"`,
`"disabledRuleIDs"`, `"excludedPaths"`) are stable across 0.x; the
Swift property names may rename to bare forms (`enabled`, `disabled`,
`excluded`) in 0.2 to remove the namespace-implicit prefix
redundancy, with a serializer-side mapping preserving wire compat. JSON
consumers built against 0.1.x continue to work after a 0.2 Swift-side
rename; Swift API consumers face a one-line migration per field.

### Five-package cohort

The implementation factors across five sibling packages:

| Package | Layer | Role |
|---------|-------|------|
| **swift-linter** (this) | L3 (Foundations) | Engine, CLI, reporters |
| swift-linter-rules | L3 | Default rule packs |
| swift-manifests | L3 | Manifest loader + parent-chain resolver |
| swift-manifest-primitives | L1 (Primitives) | `Manifest.Dependency`, `Manifest.NestedPackage` types |
| swift-linter-primitives | L1 | `Lint.Configuration`, `Lint.Rule.Protocol`, `Lint.Filter`, the typed-DSL surface |

The factorization reflects the institute's five-layer architecture: L1
primitives provide atoms (typed DSL surface, dependency-shape types);
L3 foundations compose them into running tools. A single-package
collapse would conflate the L1 typed-DSL surface (consumer-facing
type vocabulary) with the L3 engine (running orchestration), breaking
the layering. Consumers depend on `swift-linter` via the URL-form
`.package(url:from:)` declaration; the cohort's primitives are pulled
transitively.

## Documentation

A DocC catalog covering the rule catalog, configuration schema, and CI
integration recipes is deferred to a separate cycle.

## License

Apache 2.0. See [LICENSE.md](LICENSE.md).
