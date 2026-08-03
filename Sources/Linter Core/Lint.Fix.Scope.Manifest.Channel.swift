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

extension Lint.Fix.Scope.Manifest {
    /// Environment channel carrying the declared package-manifest path
    /// eligible for `--fix`'s manifest scope, from the coordinator to
    /// either dispatched linter executable.
    ///
    /// Mirrors ``Lint/Fix/Scope/Channel`` (the target-root channel) in
    /// shape and discipline, for a single optional path rather than a
    /// vector: unset ⇒ `nil` ⇒ no manifest scope, matching every
    /// invocation that predates `--fix-manifest`.
    public enum Channel {}
}

extension Lint.Fix.Scope.Manifest.Channel {
    /// The environment variable carrying the JSON-encoded manifest path.
    public static let variable: Swift.String = "SWIFT_LINTER_FIX_MANIFEST"

    /// Encodes the exact declared manifest path for transport to a
    /// dispatched executable.
    public static func value(_ path: File.Path) -> Swift.String {
        JSON.string(path.string).jsonString()
    }

    /// Reads the declared manifest path supplied by the coordinator.
    ///
    /// `nil` means the channel is unset — no manifest scope for this run.
    public static func read() throws(Error) -> File.Path? {
        guard let raw: Swift.String = Environment.read(Self.variable) else {
            return nil
        }
        return try resolve(raw)
    }

    /// Resolves the set-channel case without reading process state.
    internal static func resolve(_ raw: Swift.String) throws(Error) -> File.Path {
        let parsed: JSON
        do throws(JSON.Error) {
            parsed = try JSON.parse(raw)
        } catch {
            throw .unparseable(value: raw, description: "\(error)")
        }
        guard parsed.isString else {
            throw .unparseable(value: raw, description: "expected a JSON string")
        }
        let string = Swift.String(parsed)
        do throws(Paths.Path.Error) {
            return try File.Path(string)
        } catch {
            throw .invalid(path: string, description: "\(error)")
        }
    }
}
