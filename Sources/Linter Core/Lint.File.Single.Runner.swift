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

internal import Environment
internal import File_System
internal import Process

extension Lint.File.Single {
    /// The fast-path spawn: hand a Shape-γ consumer's lint to the prebuilt
    /// "standard runner" rather than materializing + compiling a per-run eval
    /// project. ``dispatch(at:arguments:output:nonce:)`` calls
    /// ``run(binary:consumerPackageRoot:arguments:selection:nonce:)`` once the
    /// classifier has confirmed the consumer's active rule set is exactly the
    /// set the runner bakes.
    public enum Runner: Swift.Sendable {}
}

extension Lint.File.Single.Runner {
    /// Spawn the prebuilt "standard runner" to lint the consumer's declared
    /// targets, returning its exit code.
    ///
    /// Mirrors ``Manifest/Executable/dispatch(configuration:)``'s spawn shape —
    /// `/usr/bin/env <runner> <arguments>` via ``Process/Spawn`` with the
    /// parent's stdio inherited — so the runner's diagnostic stdout streams
    /// straight through to the caller. `environment: nil` inherits the parent
    /// environment (PATH, the toolchain runtime paths) per ``Process/Spawn``
    /// semantics.
    ///
    /// `arguments` is the consumer's forwarded CLI argument vector (the
    /// lint-target paths). It is forwarded VERBATIM (see ``invocation(binary:arguments:)``)
    /// so the fast path lints exactly the paths the eval path lints.
    ///
    /// A terminating signal `s` is encoded as `-s`, matching the eval-path
    /// convention, so callers distinguish abnormal termination from a non-zero
    /// exit.
    ///
    /// When `selection` is non-`nil` (a pure-bundle consumer with
    /// `.excluding(rules:)`), it is written via ``Channel/selection`` (a
    /// per-run-unique file under `<consumerRoot>/.swift-lint/`) and the path is
    /// passed to the runner in the channel's environment variable; the runner's
    /// `Lint.run(bundle:)` reads it via ``Channel/read()`` and overlays it on
    /// its baked registry so it lints `Bundle.primitives` minus the consumer's
    /// exclusions. `nil` runs the full baked bundle (bare-bundle consumer).
    internal static func run(
        binary: Swift.String,
        consumerPackageRoot: File.Path,
        arguments: [Swift.String],
        selection: Lint.Manifest?,
        nonce: Swift.String
    ) throws(Lint.File.Single.Error) -> Swift.Int32 {
        let environment: [Swift.String: Swift.String]?
        if let selection: Lint.Manifest = selection {
            let manifestPath: File.Path
            do throws(Lint.File.Single.Channel.Error) {
                manifestPath = try Lint.File.Single.Channel.selection.write(
                    selection,
                    consumerPackageRoot: consumerPackageRoot,
                    nonce: nonce
                )
            } catch {
                throw .materializationFailed(reason: "write selection manifest: \(error)")
            }
            var snapshot: Environment.Snapshot = Environment.Snapshot.current()
            snapshot.values[Lint.File.Single.Channel.selection.variable] = manifestPath.string
            environment = snapshot.values
        } else {
            environment = nil  // inherit the parent environment
        }
        let invocation: [Swift.String] = Self.invocation(binary: binary, arguments: arguments)
        let spawnConfiguration = Process.Spawn.Configuration(
            executable: "/usr/bin/env",
            arguments: invocation,
            environment: environment
        )
        let status: Process.Status
        do throws(Process.Error) {
            status = try Process.Spawn.run(spawnConfiguration).status
        } catch {
            throw .spawnFailed(
                consumerPackageRoot: consumerPackageRoot,
                description: "standard-runner spawn failed: \(error)"
            )
        }
        switch status {
        case .exited(let code): return code
        case .signaled(let signal): return -signal
        case .stopped(let signal): return -signal
        }
    }

    /// Build the prebuilt-runner invocation argv: the runner `binary` followed
    /// by the consumer's forwarded CLI `arguments` (the lint-target paths).
    ///
    /// Forwarding `arguments` verbatim is what keeps the fast path and the eval
    /// path in lock-step: ``Manifest/Executable/dispatch(configuration:)``
    /// builds `["swift", "run", …, "Lint"] + configuration.arguments`, the same
    /// vector. So a multi-path invocation (`swift-linter Sources Tests`) lints
    /// `Sources` AND `Tests` on BOTH paths, and an empty `arguments` falls
    /// through to ``Lint/run(configuration:)``'s `["."]` default on both. The
    /// earlier `[binary, consumerPackageRoot.string]` form ignored `arguments`
    /// entirely — the fast path silently linted only the package root, a
    /// wrong-result-that-exits-0 divergence from the eval path.
    ///
    /// Pure + `internal` so the forwarding contract is unit-testable without a
    /// real ``Process/Spawn``.
    internal static func invocation(
        binary: Swift.String,
        arguments: [Swift.String]
    ) -> [Swift.String] {
        [binary] + arguments
    }
}
