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

public import File_System

extension Lint.File.Single {
    /// The linter's per-consumer state directory, `<consumerPackageRoot>/.swift-lint/`.
    ///
    /// Everything the coordinator materializes for a run lands here: the per-run
    /// channel manifests (``Lint/File/Single/Channel``) and the eval package
    /// (``Lint/File/Single/Eval``). It is regenerable tool state, never package
    /// content, and it is large — an eval project runs to thousands of files.
    ///
    /// It sits inside the consumer's worktree because the dispatched child
    /// process resolves against the consumer's own package root, so the state
    /// has to be reachable from there. That placement is deliberate, and it puts
    /// the burden of not polluting the consumer's `git status` on this type:
    /// ``create(consumerPackageRoot:)`` stamps the directory with a `.gitignore`
    /// of `*`, so the directory ignores itself the moment it exists.
    ///
    /// Self-ignoring is the only mechanism that holds across the whole fleet. A
    /// rule in each consumer's own `.gitignore` would have to be propagated to
    /// every package that is ever linted and re-propagated to every package
    /// added afterwards; the stamp arrives with the directory it describes, so
    /// there is nothing to converge and nothing to drift.
    public enum State {}
}

extension Lint.File.Single.State {
    /// The state directory for `consumerPackageRoot`.
    public static func directory(consumerPackageRoot: File.Path) -> File.Path {
        consumerPackageRoot / ".swift-lint"
    }

    /// Create the state directory and stamp it self-ignoring, returning its path.
    ///
    /// Idempotent: the directory is created recursively and the `.gitignore` is
    /// rewritten atomically on every call, so an existing directory that predates
    /// the stamp acquires it on the next run rather than staying unignored.
    public static func create(
        consumerPackageRoot: File.Path
    ) throws(Error) -> File.Path {
        let directory: File.Path = Self.directory(consumerPackageRoot: consumerPackageRoot)
        do throws(File.System.Create.Directory.Error) {
            try File.Directory(directory).create.recursive()
        } catch {
            throw .creationFailed(path: directory, description: "\(error)")
        }
        let marker: File.Path = directory / ".gitignore"
        do throws(File.System.Write.Atomic.Error) {
            try File(marker).write.atomic("*\n")
        } catch {
            throw .creationFailed(path: marker, description: "\(error)")
        }
        return directory
    }
}

extension Lint.File.Single.State {
    /// A failure to materialize the state directory or its self-ignoring stamp.
    public enum Error: Swift.Error, Equatable, Sendable {
        case creationFailed(path: File.Path, description: Swift.String)
    }
}
