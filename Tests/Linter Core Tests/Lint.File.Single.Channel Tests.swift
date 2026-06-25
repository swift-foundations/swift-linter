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

import Foundation
import File_System
import Testing
@testable import Linter_Core

extension Lint.File.Single.Channel {
    @Suite
    struct Test {}
}

// MARK: - Lint.File.Single.Channel
//
// Hole 1b regression + the unified symmetric IPC contract. The selection and
// parent channels both:
//   - read() == nil ONLY when the variable is UNSET (legitimate "no overlay");
//   - HARD-ERROR (throw) when the variable is SET but the file is
//     missing / unreadable / unparseable — NEVER a silent fall-through that
//     would widen to the full baked bundle (re-firing an excluded rule) or
//     silently drop a parent's rules.
// The fail-loud SET path is exercised through `resolve(raw:)`, which is the
// SET case in isolation (no process-env mutation required).

extension Lint.File.Single.Channel.Test {
    /// Foundation-backed fixture dir (tests are exempt from PRIM-FOUND). A
    /// broken temp environment here is a broken test, not a runtime fault —
    /// `try!` is the right shape, matching `Lint.Suppression Tests`.
    private static func freshRoot() -> File.Path {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lint-channel-fixture-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try! File.Path(directory.path)
    }

    private static func writeFile(_ content: Swift.String) -> File.Path {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lint-channel-file-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("manifest.json")
        try! content.data(using: .utf8)!.write(to: file)
        return try! File.Path(file.path)
    }

    @Test
    func `An UNSET channel variable reads as nil (no overlay)`() throws {
        // A variable guaranteed unset in the test environment — only an UNSET
        // variable is a legitimate nil.
        let channel = Lint.File.Single.Channel(
            variable: "SWIFT_LINTER_TEST_DEFINITELY_UNSET_8F3A2B",
            basename: "test-manifest"
        )
        let manifest = try channel.read()
        #expect(manifest == nil)
    }

    @Test
    func `A SET-but-missing manifest HARD-ERRORS, never silently widens`() {
        // THE 1b regression: the SET case with a missing file must THROW —
        // it must NEVER return nil (which the runner would read as "no overlay"
        // → lint the FULL baked bundle → re-fire an EXCLUDED rule, exit 0).
        let channel = Lint.File.Single.Channel.selection
        do throws(Lint.File.Single.Channel.Error) {
            _ = try channel.resolve(raw: "/nonexistent/swift-linter-test/selection-manifest.json")
            Issue.record("resolve(raw:) must throw for a set-but-missing manifest, not return a value")
        } catch {
            switch error {
            case .unreadable:
                break  // expected
            default:
                Issue.record("expected .unreadable, got \(error)")
            }
        }
    }

    @Test
    func `A SET-but-malformed manifest HARD-ERRORS as unparseable`() {
        let path = Self.writeFile("this is not valid json {{{")
        let channel = Lint.File.Single.Channel.parent
        do throws(Lint.File.Single.Channel.Error) {
            _ = try channel.resolve(raw: path.string)
            Issue.record("resolve(raw:) must throw for a malformed manifest")
        } catch {
            switch error {
            case .unparseable:
                break  // expected
            default:
                Issue.record("expected .unparseable, got \(error)")
            }
        }
    }

    @Test
    func `Write then resolve round-trips the manifest`() throws {
        let root = Self.freshRoot()
        let manifest = Lint.Manifest(disabled: ["raw value access", "int public parameter"])
        let written = try Lint.File.Single.Channel.selection.write(
            manifest,
            consumerPackageRoot: root,
            nonce: "abc123"
        )
        let read = try Lint.File.Single.Channel.selection.resolve(raw: written.string)
        #expect(read == manifest)
    }

    @Test
    func `The nonce makes the temp-file name unique per run`() throws {
        let root = try File.Path("/tmp/swift-linter-nonce-test")
        let fixed = try Lint.File.Single.Channel.selection.path(consumerPackageRoot: root, nonce: "")
        let unique = try Lint.File.Single.Channel.selection.path(consumerPackageRoot: root, nonce: "deadbeef")
        #expect(fixed.string.hasSuffix("selection-manifest.json"))
        #expect(unique.string.hasSuffix("selection-manifest-deadbeef.json"))
        #expect(fixed != unique)
    }
}
