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

import File_System
import Testing

@testable import Linter_Core

extension Lint.File.Single.State {
    @Suite
    struct Test {}
}

// MARK: - Lint.File.Single.State
//
// The state directory lives inside the consumer's worktree and holds thousands
// of files (the eval project). It must ignore itself the moment it exists —
// a `.gitignore` of `*` stamped by whoever creates the directory — because the
// alternative is a rule propagated into every package that is ever linted, and
// re-propagated into every package added afterwards.
//
// Fixtures use the institute `File_System` temp APIs (Foundation-free per
// [PRIM-FOUND-001]); a broken temp environment is a broken test, not a runtime
// fault, so `try!` is the right shape for setup.

extension Lint.File.Single.State.Test {
    private static func freshRoot(key: Swift.String) -> File.Path {
        // swift-format-ignore: NeverUseForceTry
        try! File.Path.Temporary.deterministic(prefix: "lint-state-root-", key: key, suffix: "")
    }

    @Test
    func `Creating the state directory stamps it self-ignoring`() throws {
        let root: File.Path = Self.freshRoot(key: "stamp")
        let directory: File.Path = try Lint.File.Single.State.create(consumerPackageRoot: root)

        #expect(directory == Lint.File.Single.State.directory(consumerPackageRoot: root))
        let marker: Swift.String = try Lint.File.Single.contents(of: directory / ".gitignore")
        #expect(marker == "*\n")
    }

    @Test
    func `Creation is idempotent, so a directory predating the stamp acquires it`() throws {
        let root: File.Path = Self.freshRoot(key: "idempotent")

        // A state directory that exists without the stamp — the shape every
        // checkout that ran the linter before this change is in.
        let directory: File.Path = Lint.File.Single.State.directory(consumerPackageRoot: root)
        try File.Directory(directory).create.recursive()

        _ = try Lint.File.Single.State.create(consumerPackageRoot: root)
        _ = try Lint.File.Single.State.create(consumerPackageRoot: root)

        let marker: Swift.String = try Lint.File.Single.contents(of: directory / ".gitignore")
        #expect(marker == "*\n")
    }

    @Test
    func `A channel write stamps the directory it writes into`() throws {
        let root: File.Path = Self.freshRoot(key: "channel")
        let channel: Lint.File.Single.Channel = .selection

        let target: File.Path = try channel.write(
            Lint.Manifest(),
            consumerPackageRoot: root,
            nonce: ""
        )

        #expect(
            target.string.hasPrefix(
                Lint.File.Single.State.directory(consumerPackageRoot: root).string
            )
        )
        let marker: Swift.String = try Lint.File.Single.contents(
            of: Lint.File.Single.State.directory(consumerPackageRoot: root) / ".gitignore"
        )
        #expect(marker == "*\n")
    }
}
