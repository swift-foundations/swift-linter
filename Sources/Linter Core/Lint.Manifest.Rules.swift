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

public import Linter_Primitives

extension Lint.Manifest {
    /// Property.View on ``Lint/Manifest`` for rule-related leaves.
    public struct Rules: Sendable, Hashable {
        /// Rule IDs to activate at this manifest's layer.
        public let enabled: Set<Lint.Rule.ID>

        /// Rule IDs to deactivate at this manifest's layer. Layered
        /// with parent inheritance per the Configuration's
        /// ``Lint/Configuration/Rules/effective`` override semantics.
        public let disabled: Set<Lint.Rule.ID>

        public init(
            enabled: Set<Lint.Rule.ID> = [],
            disabled: Set<Lint.Rule.ID> = []
        ) {
            self.enabled = enabled
            self.disabled = disabled
        }
    }
}
