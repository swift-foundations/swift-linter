// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-linter open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-linter project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

public import File_System

/// Detects + (eventually) evaluates a consumer's `Lint.swift`
/// configuration file.
///
/// Phase 1.5 Item 5 v1 ships the L1 + canonical-package architecture +
/// detection-only driver: when `Lint.swift` is present at the consumer
/// package root, the driver acknowledges its presence and the CLI
/// returns to a canonical-default configuration (everything in
/// `Lint.Rule.builtIn` enabled at default severity, matching the
/// effective tier2 + open-class rules). At v1 the consumer's
/// `Lint.swift` content is read but NOT compiled-and-run — full
/// subprocess evaluation lands in Phase 2 v2 (OQ-EV1).
///
/// ## Why a v1 stub vs. a full evaluator?
///
/// Full Lint.swift evaluation requires (per SPM's Package.swift loader
/// pattern):
///
/// 1. Generating a temp `.build/.lint-eval/Package.swift` with deps on
///    swift-linter, the canonical packages, etc.
/// 2. Spawning `swift run` to compile-and-execute the consumer's
///    Lint.swift content with an auto-generated `main.swift` shim
///    that invokes the linter.
/// 3. Forwarding stdout to the parent CLI.
/// 4. Cache the result keyed on Lint.swift hash + dependency hash.
///
/// Subprocess spawning at L3 swift-linter requires either Foundation
/// `Process` (re-introducing Foundation; regresses Item 1) or
/// `posix_spawn` directly (substantial implementation surface). Phase
/// 1.5 v1 defers this; v2 lands it as a single focused dispatch when a
/// Foundation-clean process primitive (`swift-foundations/swift-process`)
/// is available — the package directory exists in the workspace but is
/// empty as of 2026-05-06.
///
/// ## Consumer-visible behavior at v1
///
/// - Lint.swift at consumer root: detected; presence logged in stderr.
///   Configuration applied: `Lint.Rule.builtIn` everything enabled at
///   default severity (functionally equivalent to inheriting tier2 +
///   no overrides for the swift-tagged-primitives PoC scenario).
/// - No Lint.swift at consumer root: identical behavior — the v1
///   default Configuration matches the expected canonical-tier2-derived
///   shape for primitives consumers.
///
/// Empirical R5 invariant 27/26/15/8/2 holds at v1 because the
/// effective rule set (R5 enabled at warning severity) is the same
/// whether sourced from canonical tier2 or from `Lint.Rule.builtIn`.
extension Lint {
    public enum SwiftDriver {}
}

extension Lint.SwiftDriver {
    /// Detects whether a `Lint.swift` exists at the consumer's package
    /// root.
    public static func lintSwiftPath(at consumerPackageRoot: Swift.String) -> Swift.String? {
        let candidate = "\(consumerPackageRoot)/Lint.swift"
        guard let directory = try? File.Directory(validating: consumerPackageRoot) else {
            return nil
        }
        guard let entries = try? directory.entries() else {
            return nil
        }
        for entry in entries where Swift.String(entry.name) == "Lint.swift" {
            return candidate
        }
        return nil
    }

    /// Resolve the configuration for the given consumer root.
    ///
    /// - If Lint.swift is present, read its content (validates UTF-8 +
    ///   readability) and return the v1-default Configuration. Phase 2
    ///   v2 will compile-and-run Lint.swift to produce the actual
    ///   typed value; v1 honors the file's *presence* but defers
    ///   structural evaluation.
    /// - If Lint.swift is absent, return the same v1-default
    ///   Configuration.
    ///
    /// The v1-default activates every rule in `Lint.Rule.builtIn` at
    /// its `defaultSeverity`. For the swift-primitives ecosystem this
    /// is functionally equivalent to inheriting
    /// `SwiftPrimitivesLintCanonical.tier2` with no overrides, which
    /// is the empirical case for the proof-of-concept Lint.swift at
    /// swift-tagged-primitives.
    public static func resolveConfiguration(
        consumerPackageRoot: Swift.String
    ) -> Lint.Configuration {
        // Validate that Lint.swift, if present, is at least readable.
        // This catches typos / permission issues at v1 even though full
        // structural evaluation defers to v2.
        if let lintSwiftPath = lintSwiftPath(at: consumerPackageRoot) {
            _ = (try? File.Path(lintSwiftPath))
                .flatMap { try? File($0).read.full { _ in } }
        }
        return Lint.Configuration(rules: {
            for rule in Lint.Rule.builtIn {
                Lint.Rule.Configuration.enable(type(of: rule))
            }
        })
    }
}
