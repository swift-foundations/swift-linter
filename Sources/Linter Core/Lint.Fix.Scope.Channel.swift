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

extension Lint.Fix.Scope {
    /// Environment channel carrying declared target roots from the coordinator
    /// to either dispatched linter executable.
    public enum Channel {}
}

extension Lint.Fix.Scope.Channel {
    /// The environment variable carrying the JSON target-root vector.
    public static let variable: Swift.String = "SWIFT_LINTER_FIX_TARGETS"

    /// Encodes exact declared target roots for transport to a dispatched
    /// executable.
    public static func value(_ roots: [File.Path]) -> Swift.String {
        JSON.array(roots.map { .string($0.string) }).jsonString()
    }

    /// Reads the declared target roots supplied by the coordinator.
    ///
    /// `nil` means the channel is unset. A fix entry point treats that as a
    /// hard error because silently widening to the package root could rewrite
    /// files that belong to no declared target.
    public static func read() throws(Error) -> [File.Path]? {
        guard let raw: Swift.String = Environment.read(Self.variable) else {
            return nil
        }
        return try resolve(raw)
    }

    /// Resolves the set-channel case without reading process state.
    internal static func resolve(_ raw: Swift.String) throws(Error) -> [File.Path] {
        let parsed: JSON
        do throws(JSON.Error) {
            parsed = try JSON.parse(raw)
        } catch {
            throw .unparseable(value: raw, description: "\(error)")
        }

        let strings: [Swift.String]
        do throws(JSON.Error) {
            strings = try [Swift.String](json: parsed)
        } catch {
            throw .unparseable(value: raw, description: "\(error)")
        }

        var roots = [File.Path]()
        roots.reserveCapacity(strings.count)
        for string in strings {
            do throws(Paths.Path.Error) {
                roots.append(try File.Path(string))
            } catch {
                throw .invalid(path: string, description: "\(error)")
            }
        }
        return roots
    }
}
