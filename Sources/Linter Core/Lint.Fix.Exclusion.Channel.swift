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
internal import JSON

extension Lint.Fix.Exclusion {
    /// Environment channel carrying rule IDs withheld from fix application.
    public enum Channel {}
}

extension Lint.Fix.Exclusion.Channel {
    /// The environment variable carrying the JSON rule-ID set.
    public static let variable: Swift.String = "SWIFT_LINTER_FIX_EXCLUDING_RULES"

    /// Encodes canonical rule IDs for transport to a dispatched executable.
    public static func value(_ rules: Set<Lint.Rule.ID>) -> Swift.String {
        JSON.array(rules.map { .string($0.underlying) }).jsonString()
    }

    /// Reads the rule IDs withheld by the coordinator.
    ///
    /// `nil` means no rules are withheld. IDs are intentionally not validated
    /// against the receiving configuration: callers may share one set across
    /// packages, and an ID absent from this package cannot affect its fixes.
    public static func read() throws(Error) -> Set<Lint.Rule.ID>? {
        guard let raw: Swift.String = Environment.read(Self.variable) else {
            return nil
        }
        return try resolve(raw)
    }

    /// Resolves the set-channel case without reading process state.
    internal static func resolve(_ raw: Swift.String) throws(Error) -> Set<Lint.Rule.ID> {
        let parsed: JSON
        do throws(JSON.Error) {
            parsed = try JSON.parse(raw)
        } catch {
            throw .unparseable(value: raw, description: "\(error)")
        }

        let identifiers: [Swift.String]
        do throws(JSON.Error) {
            identifiers = try [Swift.String](json: parsed)
        } catch {
            throw .unparseable(value: raw, description: "\(error)")
        }

        return Set(identifiers.map { Lint.Rule.ID(_unchecked: $0) })
    }
}
