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
public import File_System
internal import JSON

extension Lint.File.Single {
    /// A symmetric env-var + temp-file IPC channel carrying a serialized
    /// `Lint.Manifest` from the swift-linter coordinator to a dispatched
    /// executable (the prebuilt runner or the eval-compiled `Lint`).
    ///
    /// Two channels exist, differing ONLY in their environment variable and
    /// temp-file basename:
    /// - ``selection`` — a fast-path consumer's own `.excluding(rules:)`
    ///   overlay, written by the coordinator and read by the prebuilt runner's
    ///   `Lint.run(bundle:)`.
    /// - ``parent`` — the folded `// parent:` inheritance chain, written by the
    ///   coordinator and read by the eval-compiled `Lint`'s
    ///   `Lint.run(dependencies:rules:)`.
    ///
    /// Unifying both behind one type collapses two previously-divergent IPC
    /// protocols into a single symmetric one — and is where the fail-loud
    /// guarantee lives:
    ///
    /// ``read()`` returns `nil` ONLY when the channel's variable is UNSET (a
    /// legitimate "no overlay"). When the variable is SET, the file MUST read,
    /// parse, and deserialize, or ``read()`` HARD-ERRORS (throws ``Error``). It
    /// NEVER silently returns `nil`. This makes the prior silent widen —
    /// `selectionManifest()` swallowing every read failure → `nil` → the FULL
    /// baked bundle, re-firing an EXCLUDED rule — unrepresentable. The parent
    /// channel inherits the same guarantee: a set-but-unreadable parent
    /// manifest can no longer silently drop the parent's rules.
    public struct Channel: Swift.Sendable {
        /// The environment variable carrying the temp-file path from the
        /// coordinator (writer) to the dispatched executable (reader).
        public let variable: Swift.String

        /// The temp-file basename stem under `<consumerRoot>/.swift-lint/`. A
        /// per-run nonce and `.json` are appended by
        /// ``path(consumerPackageRoot:nonce:)``.
        public let basename: Swift.String

        @inlinable
        public init(variable: Swift.String, basename: Swift.String) {
            self.variable = variable
            self.basename = basename
        }
    }
}

extension Lint.File.Single.Channel {
    /// The selection-overlay channel: a fast-path consumer's own
    /// `.excluding(rules:)` set. The coordinator writes it; the prebuilt
    /// standard runner reads it and overlays it on its baked registry so it
    /// lints `Bundle.primitives` MINUS the consumer's exclusions.
    public static let selection = Self(
        variable: "SWIFT_LINTER_SELECTION_MANIFEST",
        basename: "selection-manifest"
    )

    /// The parent-inheritance channel: the folded `// parent:` chain. The
    /// coordinator writes it; the eval-compiled `Lint` reads and lifts it
    /// against the local rule registry as the `inheriting:` configuration.
    public static let parent = Self(
        variable: "SWIFT_LINTER_PARENT_MANIFEST",
        basename: "parent-manifest"
    )
}

extension Lint.File.Single.Channel {
    /// The per-run temp-file path this channel writes to, under
    /// `<consumerPackageRoot>/.swift-lint/`.
    ///
    /// `nonce` makes the path unique per coordinator run (2f): two concurrent
    /// `swift-linter` invocations on the same consumer root no longer clobber a
    /// single FIXED `<basename>.json`. An empty `nonce` (the library / test
    /// default, always single-process) keeps the stable `<basename>.json` name.
    /// The reader never reconstructs this path — it takes the full path from
    /// ``variable`` — so the nonce is the writer's concern only.
    internal func path(
        consumerPackageRoot: File.Path,
        nonce: Swift.String
    ) throws(Paths.Path.Error) -> File.Path {
        let name: Swift.String = nonce.isEmpty ? "\(basename).json" : "\(basename)-\(nonce).json"
        // `name` is a runtime string (one component, no separators) — construct
        // a typed relative `File.Path` and append it, mirroring
        // `File.Path.Temporary.deterministic`. The `/` operator only accepts a
        // compile-time `Path.Component` literal.
        let trailing: File.Path = try File.Path(name)
        return (consumerPackageRoot / ".swift-lint").appending(trailing)
    }

    /// Coordinator side: serialize `manifest` to this channel's per-run file
    /// under `<consumerPackageRoot>/.swift-lint/` and return its path. The
    /// caller sets ``variable`` to the returned path in the dispatched
    /// process's environment.
    public func write(
        _ manifest: Lint.Manifest,
        consumerPackageRoot: File.Path,
        nonce: Swift.String
    ) throws(Error) -> File.Path {
        let directory: File.Path = consumerPackageRoot / ".swift-lint"
        do throws(File.System.Create.Directory.Error) {
            try File.Directory(directory).create.recursive()
        } catch {
            throw .writeFailed(variable: variable, description: "create directory \(directory.string): \(error)")
        }
        let target: File.Path
        do throws(Paths.Path.Error) {
            target = try self.path(consumerPackageRoot: consumerPackageRoot, nonce: nonce)
        } catch {
            throw .writeFailed(variable: variable, description: "compose manifest path: \(error)")
        }
        let json: Swift.String = Lint.Manifest.serialize(manifest).jsonString()
        do throws(File.System.Write.Atomic.Error) {
            try File(target).write.atomic(json)
        } catch {
            throw .writeFailed(variable: variable, description: "write \(target.string): \(error)")
        }
        return target
    }

    /// Dispatched side: read the `Lint.Manifest` this channel carries.
    ///
    /// Returns `nil` ONLY when ``variable`` is UNSET (no overlay). When the
    /// variable is SET, this NEVER returns `nil` — the file must read + parse +
    /// deserialize or it throws ``Error`` (fail loud; see the type doc).
    public func read() throws(Error) -> Lint.Manifest? {
        guard let raw: Swift.String = Environment.read(variable) else {
            return nil  // UNSET → legitimate "no overlay"
        }
        return try self.resolve(raw: raw)
    }

    /// Fail-loud resolution of a SET variable's raw value into a manifest. This
    /// is the SET case, so it ALWAYS throws on failure — never returns a
    /// sentinel that a caller could mistake for "no overlay". `internal` so the
    /// fail-loud contract is unit-testable without mutating the process
    /// environment.
    internal func resolve(raw: Swift.String) throws(Error) -> Lint.Manifest {
        let path: File.Path
        do throws(Paths.Path.Error) {
            path = try File.Path(raw)
        } catch {
            throw .invalidPath(variable: variable, raw: raw, description: "\(error)")
        }
        let source: Swift.String
        do throws(File.System.Read.Full.Error) {
            source = try Lint.File.Single.contents(of: path)
        } catch {
            throw .unreadable(variable: variable, path: path, description: "\(error)")
        }
        let parsed: JSON
        do throws(JSON.Error) {
            parsed = try JSON.parse(source)
        } catch {
            throw .unparseable(variable: variable, path: path, description: "\(error)")
        }
        let manifest: Lint.Manifest
        do throws(JSON.Error) {
            manifest = try Lint.Manifest.deserialize(parsed)
        } catch {
            throw .unparseable(variable: variable, path: path, description: "\(error)")
        }
        return manifest
    }
}
