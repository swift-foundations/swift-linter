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

## How it complements SwiftLint and swift-format

`swift-linter` is not a replacement for either tool; the three are
complementary:

| Tool | Rule shape | Use for |
|------|-----------|---------|
| [swift-format](https://github.com/swiftlang/swift-format) | Whitespace and formatting normalizer | Indentation, line wrapping, brace placement |
| [SwiftLint](https://github.com/realm/SwiftLint) | Regex / token patterns over source text | Style conventions, simple structural rules |
| **swift-linter** (this package) | SwiftSyntax AST predicates | Ownership / typed-system / spec-mirror rules whose predicates can't be expressed as regex |

Use all three together: `swift-format` for normalization, SwiftLint for
fast token-level rules, swift-linter for AST-shaped rules the other
two cannot reach.

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

## Adopting the `Lint/` shape

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

`Lint/Sources/Lint/main.swift` registers the imported rules and emits
the manifest:

```swift
// Lint/Sources/Lint/main.swift
import Linter
import Linter_Rule_Unchecked
import Linter_Rule_Cardinal

let manifest = Lint.Manifest(
    enabledRuleIDs: [
        Lint.Rule.Unchecked.id,
        Lint.Rule.Cardinal.Count.id,
    ],
    excludedPaths: [
        try File.Path("Tests/Fixtures"),
        try File.Path(".build"),
    ]
)
```

`swift run swift-linter <package>` discovers `Lint/`, builds it as a
nested SwiftPM package, executes its emitted manifest, and runs the
configured rules across the parent package's source tree.

## Inheritance via `// parent:` directive

Layer your manifest on top of a canonical configuration hosted at a
URL. Place the directive in the first 30 lines of `Lint.swift` (or
`Lint/Sources/Lint/main.swift`):

```swift
// parent: https://raw.githubusercontent.com/<your-org>/.github/main/Lint.swift
import Linter

let manifest = Lint.Manifest(enabledRuleIDs: [])  // inherit all from parent
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

## Documentation

A DocC catalog covering the rule catalog, configuration schema, and CI
integration recipes is deferred to a separate cycle.

## License

Apache 2.0. See [LICENSE.md](LICENSE.md).
