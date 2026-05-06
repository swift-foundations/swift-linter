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
import URI_Standard
@testable import Linter_Core

extension Lint.Driver {
    @Suite
    struct Test {
        @Suite struct ConfigurationFromManifest {}
        @Suite struct SanitizeForPath {}
        @Suite struct TempPathFor {}
    }
}

// MARK: - configuration(from:parent:)

extension Lint.Driver.Test.ConfigurationFromManifest {
    @Test
    func `Empty manifest with nil parent produces empty effective rules`() {
        let manifest = Lint.Manifest(enabledRuleIDs: [])
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        #expect(configuration.effectiveRules().isEmpty)
    }

    @Test
    func `Single enabled rule produces one effective entry`() {
        let manifest = Lint.Manifest(enabledRuleIDs: ["unchecked_call_site"])
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        let effective = configuration.effectiveRules()
        #expect(effective.count == 1)
        if effective.count == 1 {
            #expect(effective[0].rule.id == "unchecked_call_site")
        }
    }

    @Test
    func `Child disable overrides parent enable for same rule TYPE`() {
        // Parent: enables R5
        let parentManifest = Lint.Manifest(enabledRuleIDs: ["unchecked_call_site"])
        let parentConfiguration = Lint.Driver.configuration(
            from: parentManifest,
            parent: nil
        )
        // Child: disables R5
        let childManifest = Lint.Manifest(
            enabledRuleIDs: [],
            disabledRuleIDs: ["unchecked_call_site"]
        )
        let childConfiguration = Lint.Driver.configuration(
            from: childManifest,
            parent: parentConfiguration
        )
        // Effective: empty (parent's enable shadowed by child's disable per
        // Lint.Configuration.effectiveRules() per-TYPE override semantics).
        #expect(childConfiguration.effectiveRules().isEmpty)
    }

    @Test
    func `Child empty enabled inherits parent's enabled set`() {
        // Parent: enables R1 + R5
        let parentManifest = Lint.Manifest(
            enabledRuleIDs: ["unchecked_call_site", "cardinal_count_minus_one"]
        )
        let parentConfiguration = Lint.Driver.configuration(
            from: parentManifest,
            parent: nil
        )
        // Child: empty manifest
        let childManifest = Lint.Manifest(enabledRuleIDs: [])
        let childConfiguration = Lint.Driver.configuration(
            from: childManifest,
            parent: parentConfiguration
        )
        // Effective: parent's two rules (child adds nothing, disables nothing).
        let effectiveIDs: Set<Lint.Rule.ID> = Set(
            childConfiguration.effectiveRules().map { $0.rule.id }
        )
        #expect(effectiveIDs == ["unchecked_call_site", "cardinal_count_minus_one"])
    }

    @Test
    func `Excluded paths are carried through to Configuration`() throws {
        let manifest = Lint.Manifest(
            enabledRuleIDs: [],
            excludedPaths: [
                try File.Path("Tests/Fixtures"),
                try File.Path(".build"),
            ]
        )
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        #expect(configuration.excluded == ["Tests/Fixtures", ".build"])
    }

    @Test
    func `Unknown rule ID is silently ignored`() {
        let manifest = Lint.Manifest(enabledRuleIDs: ["nonexistent_rule"])
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        #expect(configuration.effectiveRules().isEmpty)
    }
}

// MARK: - sanitizeForPath

extension Lint.Driver.Test.SanitizeForPath {
    @Test
    func `Alphanumerics are retained`() {
        #expect(Lint.Driver.sanitizeForPath("abcXYZ123") == "abcXYZ123")
    }

    @Test
    func `Underscore hyphen and dot are retained`() {
        #expect(Lint.Driver.sanitizeForPath("a_b-c.d") == "a_b-c.d")
    }

    @Test
    func `Slashes are replaced with underscores`() {
        #expect(
            Lint.Driver.sanitizeForPath("https://example.com/path/file.swift")
            == "https___example.com_path_file.swift"
        )
    }

    @Test
    func `Distinct URLs produce distinct sanitized forms`() {
        let urlA = "https://a.example.com/Lint.swift"
        let urlB = "https://b.example.com/Lint.swift"
        #expect(
            Lint.Driver.sanitizeForPath(urlA)
            != Lint.Driver.sanitizeForPath(urlB)
        )
    }
}

// MARK: - tempPathFor

extension Lint.Driver.Test.TempPathFor {
    @Test
    func `Path uses tmp prefix and tmp suffix`() throws {
        let uri = try URI("https://example.com/file.swift")
        let path = Lint.Driver.tempPathFor(url: uri)
        #expect(path.hasPrefix("/tmp/swift-linter-fetch-"))
        #expect(path.hasSuffix(".tmp"))
    }

    @Test
    func `Same URL produces same path`() throws {
        let uri = try URI("https://example.com/Lint.swift")
        #expect(
            Lint.Driver.tempPathFor(url: uri)
            == Lint.Driver.tempPathFor(url: uri)
        )
    }
}
