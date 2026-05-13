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

import Testing
import File_System
import Linter_Primitives
@testable import Linter_Core

extension Lint.Driver {
    @Suite
    struct Test {
        @Suite struct ConfigurationFromManifest {}
    }
}

// MARK: - configuration(from:parent:)
//
// Post-Phase-B.1 the engine no longer ships built-in rules: the
// `Lint.Rule.builtIn` static array has been removed and
// `Lint.Driver.configuration(from:parent:)` no longer maps manifest
// `enabledRuleIDs` / `disabledRuleIDs` to rule TYPES. Rule registration
// is now the consumer's responsibility (handled in the consumer's
// `Lint/Sources/Lint/main.swift` for the nested-package shape).
//
// What the Driver still threads at this layer:
//   - parent inheritance (`Lint.Configuration(inheriting: parent, ...)`)
//   - excludedPaths from the manifest into `Lint.Configuration.excluded`
//
// The tests below pin these residual responsibilities. Per-TYPE
// override semantics (parent enable / child disable) are exercised in
// `Lint.Configuration` tests, not here, since the Driver no longer
// registers rules at either layer.

extension Lint.Driver.Test.ConfigurationFromManifest {
    @Test
    func `Empty manifest with nil parent produces empty effective rules`() {
        let manifest = Lint.Manifest()
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        #expect(configuration.rules.effective.entries.isEmpty)
    }

    @Test
    func `Manifest enabledRuleIDs are silently ignored at engine layer`() {
        // Post-decouple: the engine doesn't know about rule types, so
        // even a fully-populated enabledRuleIDs list yields no effective
        // rules at this layer.
        let manifest = Lint.Manifest(enabled: ["unchecked_call_site"])
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        #expect(configuration.rules.effective.entries.isEmpty)
    }

    @Test
    func `Manifest disabledRuleIDs are silently ignored at engine layer`() {
        // Symmetric to above: disable lists are also engine-inert
        // post-decouple — the engine has nothing to disable.
        let manifest = Lint.Manifest(
            disabled: ["unchecked_call_site"]
        )
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        #expect(configuration.rules.effective.entries.isEmpty)
    }

    @Test
    func `Child Configuration inherits from parent reference`() {
        // The Driver's job is to thread `inheriting: parent` through
        // Configuration construction. With both layers registering no
        // rules post-decouple, the effective set is empty, but the
        // inheritance link is intact (verified by Configuration-layer
        // tests).
        let parentManifest = Lint.Manifest(enabled: ["unchecked_call_site"])
        let parentConfiguration = Lint.Driver.configuration(
            from: parentManifest,
            parent: nil
        )
        let childManifest = Lint.Manifest()
        let childConfiguration = Lint.Driver.configuration(
            from: childManifest,
            parent: parentConfiguration
        )
        #expect(childConfiguration.rules.effective.entries.isEmpty)
    }

    @Test
    func `Excluded paths are carried through to Configuration`() throws(Paths.Path.Error) {
        let manifest = Lint.Manifest(
            excluded: [
                try File.Path("Tests/Fixtures"),
                try File.Path(".build"),
            ]
        )
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        #expect(configuration.excluded == ["Tests/Fixtures", ".build"])
    }

    @Test
    func `Unknown rule ID is silently ignored`() {
        // Pre-decouple: unknown IDs ignored because they didn't match
        // anything in `Lint.Rule.builtIn`. Post-decouple: ALL IDs are
        // ignored at this layer (the array is gone). This test
        // continues to assert the silent-ignore semantic.
        let manifest = Lint.Manifest(enabled: ["nonexistent_rule"])
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        #expect(configuration.rules.effective.entries.isEmpty)
    }
}
