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

extension Lint.SwiftDriver {
    @Suite
    struct Test {
        @Suite struct ParseParentURL {}
        @Suite struct ConfigurationFromManifest {}
        @Suite struct SanitizeForPath {}
        @Suite struct TempPathFor {}
    }
}

// MARK: - _parseParentURLFromContent

extension Lint.SwiftDriver.Test.ParseParentURL {
    @Test
    func `Absent directive returns nil`() {
        let content = """
        import Linter

        let manifest = Lint.Manifest(enabledRuleIDs: [])
        """
        #expect(Lint.SwiftDriver._parseParentURLFromContent(content) == nil)
    }

    @Test
    func `https URL is parsed`() throws {
        let content = """
        // parent: https://raw.githubusercontent.com/swift-institute/.github/main/Lint.swift
        import Linter
        let manifest = Lint.Manifest(enabledRuleIDs: [])
        """
        let expected = try URI(
            "https://raw.githubusercontent.com/swift-institute/.github/main/Lint.swift"
        )
        #expect(Lint.SwiftDriver._parseParentURLFromContent(content) == expected)
    }

    @Test
    func `http URL is parsed`() throws {
        let content = "// parent: http://example.com/Lint.swift\n"
        let expected = try URI("http://example.com/Lint.swift")
        #expect(Lint.SwiftDriver._parseParentURLFromContent(content) == expected)
    }

    @Test
    func `file URL is parsed`() throws {
        let content = "// parent: file:///tmp/parent.swift\n"
        let expected = try URI("file:///tmp/parent.swift")
        #expect(Lint.SwiftDriver._parseParentURLFromContent(content) == expected)
    }

    @Test
    func `Leading whitespace before directive is stripped`() throws {
        let content = "    // parent: https://example.com/Lint.swift\n"
        let expected = try URI("https://example.com/Lint.swift")
        #expect(Lint.SwiftDriver._parseParentURLFromContent(content) == expected)
    }

    @Test
    func `Tab-indented directive is parsed`() throws {
        let content = "\t// parent: https://example.com/Lint.swift\n"
        let expected = try URI("https://example.com/Lint.swift")
        #expect(Lint.SwiftDriver._parseParentURLFromContent(content) == expected)
    }

    @Test
    func `Unsupported scheme returns nil`() {
        let content = "// parent: ftp://example.com/Lint.swift\n"
        #expect(Lint.SwiftDriver._parseParentURLFromContent(content) == nil)
    }

    @Test
    func `Malformed URL without scheme returns nil`() {
        let content = "// parent: example.com/Lint.swift\n"
        #expect(Lint.SwiftDriver._parseParentURLFromContent(content) == nil)
    }

    @Test
    func `Directive past line 30 is ignored`() {
        var lines: [Swift.String] = []
        for _ in 0..<31 {
            lines.append("// padding")
        }
        lines.append("// parent: https://example.com/Lint.swift")
        let content = lines.joined(separator: "\n")
        #expect(Lint.SwiftDriver._parseParentURLFromContent(content) == nil)
    }

    @Test
    func `Directive at exactly line 30 is parsed`() throws {
        var lines: [Swift.String] = []
        for _ in 0..<29 {
            lines.append("// padding")
        }
        lines.append("// parent: https://example.com/Lint.swift")
        let content = lines.joined(separator: "\n")
        let expected = try URI("https://example.com/Lint.swift")
        #expect(Lint.SwiftDriver._parseParentURLFromContent(content) == expected)
    }

    @Test
    func `Trailing whitespace after URL is dropped`() throws {
        let content = "// parent: https://example.com/Lint.swift   \n"
        let expected = try URI("https://example.com/Lint.swift")
        #expect(Lint.SwiftDriver._parseParentURLFromContent(content) == expected)
    }

    @Test
    func `First valid directive wins when multiple are present`() throws {
        let content = """
        // parent: https://first.example.com/Lint.swift
        // parent: https://second.example.com/Lint.swift
        """
        let expected = try URI("https://first.example.com/Lint.swift")
        #expect(Lint.SwiftDriver._parseParentURLFromContent(content) == expected)
    }
}

// MARK: - _configuration(from:parent:)

extension Lint.SwiftDriver.Test.ConfigurationFromManifest {
    @Test
    func `Empty manifest with nil parent produces empty effective rules`() {
        let manifest = Lint.Manifest(enabledRuleIDs: [])
        let configuration = Lint.SwiftDriver._configuration(from: manifest, parent: nil)
        #expect(configuration.effectiveRules().isEmpty)
    }

    @Test
    func `Single enabled rule produces one effective entry`() {
        let manifest = Lint.Manifest(enabledRuleIDs: ["unchecked_call_site"])
        let configuration = Lint.SwiftDriver._configuration(from: manifest, parent: nil)
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
        let parentConfiguration = Lint.SwiftDriver._configuration(
            from: parentManifest,
            parent: nil
        )
        // Child: disables R5
        let childManifest = Lint.Manifest(
            enabledRuleIDs: [],
            disabledRuleIDs: ["unchecked_call_site"]
        )
        let childConfiguration = Lint.SwiftDriver._configuration(
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
        let parentConfiguration = Lint.SwiftDriver._configuration(
            from: parentManifest,
            parent: nil
        )
        // Child: empty manifest
        let childManifest = Lint.Manifest(enabledRuleIDs: [])
        let childConfiguration = Lint.SwiftDriver._configuration(
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
        let configuration = Lint.SwiftDriver._configuration(from: manifest, parent: nil)
        #expect(configuration.excluded == ["Tests/Fixtures", ".build"])
    }

    @Test
    func `Unknown rule ID is silently ignored`() {
        let manifest = Lint.Manifest(enabledRuleIDs: ["nonexistent_rule"])
        let configuration = Lint.SwiftDriver._configuration(from: manifest, parent: nil)
        #expect(configuration.effectiveRules().isEmpty)
    }
}

// MARK: - _sanitizeForPath

extension Lint.SwiftDriver.Test.SanitizeForPath {
    @Test
    func `Alphanumerics are retained`() {
        #expect(Lint.SwiftDriver._sanitizeForPath("abcXYZ123") == "abcXYZ123")
    }

    @Test
    func `Underscore hyphen and dot are retained`() {
        #expect(Lint.SwiftDriver._sanitizeForPath("a_b-c.d") == "a_b-c.d")
    }

    @Test
    func `Slashes are replaced with underscores`() {
        #expect(
            Lint.SwiftDriver._sanitizeForPath("https://example.com/path/file.swift")
            == "https___example.com_path_file.swift"
        )
    }

    @Test
    func `Distinct URLs produce distinct sanitized forms`() {
        let urlA = "https://a.example.com/Lint.swift"
        let urlB = "https://b.example.com/Lint.swift"
        #expect(
            Lint.SwiftDriver._sanitizeForPath(urlA)
            != Lint.SwiftDriver._sanitizeForPath(urlB)
        )
    }
}

// MARK: - _tempPathFor

extension Lint.SwiftDriver.Test.TempPathFor {
    @Test
    func `Path uses tmp prefix and tmp suffix`() throws {
        let uri = try URI("https://example.com/file.swift")
        let path = Lint.SwiftDriver._tempPathFor(url: uri)
        #expect(path.hasPrefix("/tmp/swift-linter-fetch-"))
        #expect(path.hasSuffix(".tmp"))
    }

    @Test
    func `Same URL produces same path`() throws {
        let uri = try URI("https://example.com/Lint.swift")
        #expect(
            Lint.SwiftDriver._tempPathFor(url: uri)
            == Lint.SwiftDriver._tempPathFor(url: uri)
        )
    }
}
