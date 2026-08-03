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

internal import File_System
internal import Package_Manager

extension Lint.Fix.Scope {
    /// The package manifest's fix-application scope, and the guard posture
    /// that admits it.
    ///
    /// `Package.swift` is the one file whose corruption stops a package from
    /// resolving at all, so admitting it to ``Lint/Fix/apply(paths:targets:configuration:excluding:mode:manifest:)``
    /// needs a stronger post-condition than the re-parse guard every other
    /// eligible file gets. ``evaluates(_:)`` is that stronger guard: proof
    /// the rewrite evaluates to a well-formed SwiftPM manifest, not merely
    /// that it is syntactically valid Swift. See
    /// swift-foundations/swift-linter#32 for the recorded design decision.
    ///
    /// `public`, not `internal`: it hosts ``Channel``, the cross-module
    /// transport `Lint.run(configuration:)` (target `Linter`) and the CLI
    /// (target `Linter CLI`) both read — the same reason its sibling
    /// `Lint.Fix.Scope.Channel` (target roots) is `public` too. Only
    /// ``evaluates(_:)`` itself stays `internal`: it is consumed exclusively
    /// by `Lint.Fix.apply` in this same target.
    public enum Manifest {}
}

extension Lint.Fix.Scope.Manifest {
    /// Whether `text`, materialized as a standalone `Package.swift`,
    /// evaluates under the installed SwiftPM toolchain.
    ///
    /// Runs `swift package dump-package` — via
    /// `Package.Manager.evaluation(at:)`, already the ecosystem's own
    /// `Process.Spawn`-backed wrapper for exactly that invocation — against
    /// an isolated scratch directory containing only a copy of `text`.
    /// Never the consumer's real package root: `Package.Manager.dump(at:)`
    /// takes an exclusive lock on the target directory's `.build` and waits
    /// on it indefinitely, so pointing this at a package the caller might
    /// concurrently be building would deadlock. `dump-package` does not
    /// require any other project file to exist — it evaluates the manifest
    /// script alone — so the scratch directory needs nothing beyond the one
    /// file.
    ///
    /// This is a Boolean gate, exactly like ``Lint/Fix/parses(_:)``: every
    /// failure mode — materializing the scratch copy, spawning SwiftPM, a
    /// non-zero exit, output SwiftPM's own decoder rejects — answers
    /// `false`. The caller does not need to distinguish an evaluation
    /// failure from an engine-side I/O failure; either way the manifest
    /// rewrite is refused rather than published.
    ///
    /// Bound, stated honestly: a `true` result proves the rewrite evaluates
    /// to a well-formed `Package` value under the toolchain's
    /// `PackageDescription` runtime. It does NOT prove the declared
    /// dependency/target graph is internally consistent — `dump-package`
    /// evaluates the manifest script, it does not validate the graph it
    /// describes (a target dependency naming an undeclared target still
    /// evaluates cleanly). That validation is `swift package resolve`'s
    /// job, out of scope for this guard by design: pulling resolution's
    /// network and lock semantics into every manifest fix would be a
    /// materially heavier cost than this guard exists to pay.
    internal static func evaluates(_ text: Swift.String) -> Swift.Bool {
        let key = Swift.String(Swift.UInt64.random(in: Swift.UInt64.min...Swift.UInt64.max), radix: 16)
        let directory: File.Path
        do throws(File.Path.Error) {
            directory = try File.Path.Temporary.deterministic(
                prefix: "swift-linter-fix-manifest-verify-",
                key: key,
                suffix: ""
            )
        } catch {
            return false
        }
        defer {
            do throws(File.System.Delete.Error) {
                try File.System.Delete.delete(at: directory, recursive: true)
            } catch {
                // Best-effort cleanup. A leftover OS-temp scratch directory
                // does not affect the correctness of the guard that already
                // ran and already returned its answer.
            }
        }
        do throws(File.System.Create.Directory.Error) {
            try File.Directory(directory).create.recursive()
        } catch {
            return false
        }
        do throws(File.System.Write.Atomic.Error) {
            try File(directory / "Package.swift").write.atomic(text)
        } catch {
            return false
        }
        do throws(Package.Manager.Error) {
            _ = try Package.Manager().evaluation(at: directory.string)
        } catch {
            return false
        }
        return true
    }
}
