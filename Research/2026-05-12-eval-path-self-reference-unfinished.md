# Eval-path self-reference — `path: "."` thread (unfinished)

<!--
---
version: 1.0.0
last_updated: 2026-05-12
status: DEFERRED
---
-->

## Summary

The Shape-γ `Lint.swift` consumer manifest documents `.package(path: ".")`
as a self-reference to the consumer's own package. The materializer's
`Lint.SingleFile.Materializer.resolveConsumerPath(_:relativeRoot:)`
correctly handles the path side of the self-reference (commit `595c138`
Shape γ + `fe2c18e` typed-path arithmetic) — it collapses `"."` to the
eval-root-relative path (`"../.."`). The companion fix for the
package-name side landed partially in commit `50d312b`
(`Extractor.packageName: derive self-reference basename from consumer
root`), but is **not yet end-to-end functional** when the CLI is invoked
as `swift-linter .`.

## What's broken

`Lint.SingleFile.Extractor.packageName(fromPath:consumerPackageRoot:)`
now derives the SwiftPM package name from
`basename(of: consumerPackageRoot)` when the consumer path is `"."` or
empty. This works when `consumerPackageRoot` is a real directory path
(e.g., `/Users/coen/Developer/swift-cardinal-primitives` →
`"swift-cardinal-primitives"`).

It does NOT work when the CLI is invoked from the consumer's package
root as `swift-linter .` — in that case the CLI's `paths.first` is
`"."`, and it's passed verbatim to `Lint.SingleFile.dispatch(at:arguments:)`
as `consumerPackageRoot`. The Extractor then computes
`basename(of: ".")` which is `"."` again — SwiftPM rejects the literal
`"."` as a package name with `unknown package '.'`.

## Reproducer

```bash
cd /Users/coen/Developer/swift-primitives/swift-cardinal-primitives
SWIFT_LINTER_PATH=/path/to/swift-linter ./swift-linter .
```

With a Shape-γ `Lint.swift` containing `.package(path: ".", products: [...])`,
the generated eval `Package.swift` has:

```swift
dependencies: [
    .package(path: "/Users/coen/Developer/swift-foundations/swift-linter"),
    .package(path: "../.."),           // ← path side correct
    .package(path: "../../../swift-primitives-linter-rules"),
],
targets: [
    .executableTarget(
        name: "Lint",
        dependencies: [
            .product(name: "Linter", package: "swift-linter"),
            .product(name: "Cardinal Primitives", package: "."),  // ← name side wrong
            .product(name: "Linter Primitives Rules", package: "swift-primitives-linter-rules"),
        ]
    ),
],
```

SwiftPM error: `'eval': unknown package '.' in dependencies of target 'Lint'`.

## Why deferred

No current consumer needs `path: "."`. The three numerics packages
(`swift-ordinal-primitives`, `swift-cardinal-primitives`,
`swift-affine-primitives`) — the only Shape-γ consumers loading
`Lint.Rule.Bundle.brandOwner` — use the carrier-pattern (sibling-
relative rule-pack dep only, no self-reference):

```swift
Lint.run(dependencies: [
    .package(
        path: "../swift-primitives-linter-rules",
        products: ["Linter Primitives Rules"]
    ),
]) {
    Lint.Rule.Bundle.brandOwner
}
```

The dogfood verifies the bundle exclusion works end-to-end with this
shape (zero findings from the four consumer-side rule IDs against
`swift-cardinal-primitives` whose `.rawValue` access sites would fire
under `Bundle.primitives`).

The self-reference is a **future-consumer concern**, likely needed
when the rule-pack repos themselves (`swift-linter-rules`,
`swift-institute-linter-rules`, `swift-primitives-linter-rules`)
author their own `Lint.swift` to dogfood themselves with rules they
define. At that point the self-reference is required because the
rule pack IS the consumer package.

## Fix shapes (when this becomes load-bearing)

Two options, ordered by cost:

1. **CLI-side normalization** (lowest cost, clean separation).
   In `Linter CLI/Linter CLI.swift`'s `run()`, resolve `paths.first`
   to an absolute path before passing to `Lint.SingleFile.dispatch(at:)`.
   Requires a `getcwd` primitive accessible at the CLI layer. The
   ISO 9945 primitive `ISO_9945.Kernel.Directory.Working.current(into:)`
   exists in `swift-iso-9945`; it's not currently in the CLI's dep
   graph (CLI imports `Linter` → `Linter Core`, which imports `ISO 9945`
   for terminal reporters, but the `Working.current` primitive isn't
   re-exported via Linter or Linter Core).

2. **Dispatch-level normalization**.
   In `Lint.SingleFile.dispatch(at:arguments:)`, normalize
   `consumerPackageRoot` to absolute path before threading into
   `Extractor.extractDependencies(from:sourcePath:consumerPackageRoot:)`.
   `Linter Core` already depends on `ISO 9945 Core` for the engine's
   `Source.Manager` / file IO; adding `getcwd` access at the dispatch
   site would be a smaller dep-graph touch than pulling it into the
   CLI.

Either path is ~30–50 LOC plus a test covering the
`swift-linter . → consumerPackageRoot = "." → resolved = $PWD` chain.

## What's already in place

- **Commit `50d312b`** (in `swift-foundations/swift-linter`): partial
  fix — `Lint.SingleFile.Extractor.packageName(fromPath:consumerPackageRoot:)`
  threads `consumerPackageRoot` from `Lint.SingleFile.dispatch` and
  derives the basename for self-reference. Plus 5 unit tests
  covering the four shapes (relative non-self, absolute, self-reference
  dot, self-reference empty, self-reference dot with trailing slash).
- **TODO comment** at
  `Lint.SingleFile.Extractor.packageName(fromPath:consumerPackageRoot:)`
  pointing to this doc.

## Cross-references

- Commit `595c138` (swift-foundations/swift-linter): Shape γ SingleFile
  Lint.swift dispatch with self-reference path fix — the matching
  path-side resolution.
- Commit `fe2c18e` (swift-foundations/swift-linter):
  Materializer.resolveConsumerPath typed-path arithmetic via
  File.Path — the typed-path infrastructure the path-side fix uses.
- Commit `50d312b` (swift-foundations/swift-linter):
  Extractor.packageName partial fix (this thread's current state).
- `swift-foundations/swift-linter-rules/Research/numerics-rule-recognizer-2026-05-12.md`
  v1.2.0 DECISION — the Phase B numerics Lint.swift pattern uses
  sibling-relative deps because of this unfinished thread.
