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

extension Lint.Fix.Refusal {
    /// Why the engine declined to publish a computed rewrite.
    ///
    /// Every file's guard starts at ``unparseable``. The package manifest —
    /// admitted to fix application by ``Lint/Fix/apply(paths:targets:configuration:excluding:mode:manifest:)``'s
    /// `manifest` scope — carries the additional ``manifestEvaluationFailed``
    /// guard, because re-parsing proves only that a rewrite is valid Swift
    /// syntax, not that it evaluates to a well-formed SwiftPM manifest.
    public enum Reason: Swift.Sendable, Swift.Equatable {
        /// The rewritten text did not re-parse without new syntax errors.
        case unparseable

        /// The rewritten package manifest re-parsed cleanly but did not
        /// evaluate under the installed SwiftPM toolchain (`swift package
        /// dump-package`). Reachable only for the exact `manifest` path
        /// supplied to ``Lint/Fix/apply(paths:targets:configuration:excluding:mode:manifest:)``;
        /// every other file's refusal is ``unparseable``.
        case manifestEvaluationFailed
    }
}

extension Lint.Fix.Refusal.Reason {
    /// The clause naming what went wrong, for the shared
    /// `"fix for rule '<rule>' <summary> for <path>"` report line both the
    /// dispatched-executable path (`Lint.run(configuration:)`) and the CLI's
    /// in-process fallback emit.
    ///
    /// Kept honest per-reason rather than a single shared wording: a
    /// manifest that fails evaluation DID re-parse, and reporting it as
    /// "unparseable text" would misdescribe the failure the guard actually
    /// caught.
    public var summary: Swift.String {
        switch self {
        case .unparseable:
            "produced unparseable text"

        case .manifestEvaluationFailed:
            "produced a package manifest that does not evaluate"
        }
    }
}
