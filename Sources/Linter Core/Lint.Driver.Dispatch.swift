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
internal import Manifest_Resolver

extension Lint.Driver {
    /// Namespace for nested `Lint/` SwiftPM package detection and dispatch.
    public enum Dispatch {}
}

extension Lint.Driver.Dispatch {
    /// Detect a nested `Lint/` SwiftPM package at the consumer's
    /// package root and, if present, dispatch the lint run to the
    /// consumer's `Lint` executable via
    /// `swift run --package-path <consumerRoot>/Lint Lint <args>`.
    ///
    /// PoC of the Lint/ nested-package mechanism (architecture cohort
    /// Phase A — `HANDOFF-architecture-poc-lint-nested-package.md`).
    /// Under Option 1 the Lint/ executable IS the linter binary for
    /// the consumer (linking engine + rule packs declared in its
    /// `Lint/Package.swift`); swift-linter (this CLI) becomes a
    /// coordinator that delegates the run when the consumer opts into
    /// the nested-package shape.
    ///
    /// Library output discipline: this helper does NOT write to stdout
    /// or stderr. Dispatch errors are surfaced via the optional
    /// `onDispatchError` closure; the default no-op preserves the
    /// silent-fallback behavior for non-CLI callers. The CLI binding
    /// supplies a closure that emits to `Terminal.Stream.stderr.write`
    /// so end users see a typed-error diagnostic instead of a bare
    /// non-zero exit.
    ///
    /// - Parameters:
    ///   - consumerPackageRoot: Filesystem path to the consumer's package root (the
    ///     directory containing the consumer's `Package.swift`).
    ///   - arguments: Arguments forwarded to the dispatched `Lint`
    ///     executable.
    ///   - onDispatchError: Optional closure invoked when
    ///     ``Manifest_Resolver/Manifest/NestedPackage/dispatch(at:arguments:)``
    ///     throws. Receives the error's textual description; CLI
    ///     callers translate this to a stderr diagnostic. Defaults to
    ///     a no-op so library callers retain the silent-fallback
    ///     contract.
    /// - Returns: `nil` when no nested package is detected — the
    ///   caller should fall through to the single-file `Lint.swift`
    ///   path. Otherwise the dispatched executable's exit code (an
    ///   `Int32`); `0` indicates success, non-zero indicates findings
    ///   or error per the dispatched executable's exit policy. When
    ///   the dispatch itself fails (spawn error), returns `1` after
    ///   invoking `onDispatchError`.
    public static func nested(
        at consumerPackageRoot: File.Path,
        arguments: [Swift.String],
        onDispatchError: (Swift.String) -> Void = { _ in }
    ) -> Swift.Int32? {
        // `Manifest.NestedPackage.detect / dispatch` operate at the
        // SwiftPM-shim boundary on `Swift.String` paths; convert at
        // the boundary while the engine surface above stays typed.
        let rootString: Swift.String = consumerPackageRoot.string
        guard Manifest_Resolver.Manifest.NestedPackage.detect(at: rootString) else {
            return nil
        }
        do throws(Manifest_Resolver.Manifest.NestedPackage.Error) {
            return try Manifest_Resolver.Manifest.NestedPackage.dispatch(
                at: rootString,
                arguments: arguments
            )
        } catch {
            onDispatchError("\(error)")
            return 1
        }
    }
}
