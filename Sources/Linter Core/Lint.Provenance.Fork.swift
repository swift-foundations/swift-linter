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
public import Linter_Primitives

extension Lint.Provenance {
    /// One centrally declared true fork carrying vendored upstream
    /// source, and the exact scope of that vendoring.
    ///
    /// A file is exempt from a lint run's input exactly when ALL of the
    /// following hold:
    ///
    /// 1. the run root's `Package.swift` declares this entry's
    ///    ``package`` name (``Lint/Provenance/resolve(root:)``);
    /// 2. the file's run-root-relative path lies inside a declared
    ///    ``vendored`` scope; and
    /// 3. the file itself carries the declared upstream ``attribution``
    ///    in its leading bytes.
    ///
    /// Each condition fails toward LINTING. Condition (2) draws the
    /// boundary between vendored and Institute-authored files within one
    /// fork repository: the vendored scope is an explicit enumeration
    /// owned here, so an Institute-authored addition — even inside the
    /// fork, even carrying the upstream header style — is linted unless
    /// this register deliberately covers it. Condition (3) is the
    /// per-file corroboration: a vendored slot later rewritten as
    /// Institute code without the upstream notice re-enters the linted
    /// population automatically.
    public struct Fork: Sendable, Hashable {
        /// The SwiftPM package name the fork's own `Package.swift`
        /// declares (e.g. `"swift-certificate-verification"`).
        public let package: Swift.String

        /// The asserted upstream ancestry.
        public let upstream: Upstream

        /// The literal upstream attribution every vendored file must
        /// carry in its leading bytes (e.g. the upstream copyright
        /// holder line).
        public let attribution: Swift.String

        /// The explicit run-root-relative vendored scope.
        public let vendored: [Scope]

        /// Creates a fork declaration.
        public init(
            package: Swift.String,
            upstream: Upstream,
            attribution: Swift.String,
            vendored: [Scope]
        ) {
            self.package = package
            self.upstream = upstream
            self.attribution = attribution
            self.vendored = vendored
        }
    }
}

extension Lint.Provenance.Fork {
    /// The number of leading bytes searched for ``attribution`` — the
    /// upstream notice lives in the file's header comment, and bounding
    /// the search keeps an incidental mention deep in a file from
    /// counting as attribution.
    @usableFromInline
    internal static let leading: Swift.Int = 2048

    /// Whether the walker-emitted `relativePath` under `root` is exempt
    /// vendored source per this declaration.
    ///
    /// The path scope is consulted first (cheap, no I/O); only a
    /// scope-covered file is read for the attribution check. An
    /// unreadable file resolves `false` — toward linting, where the run
    /// loop surfaces the read failure as its own typed error.
    public func exempts(relativePath: Lint.Source.Path, under root: File.Path) -> Swift.Bool {
        guard self.vendored.contains(where: { $0.matches(relativePath) }) else {
            return false
        }
        let relative: File.Path
        do throws(Paths.Path.Error) {
            relative = try File.Path(relativePath.underlying)
        } catch {
            return false
        }
        let filePath = root.appending(relative)
        let head: [Byte]
        do throws(Either<File.System.Read.Full.Error, Never>) {
            head = try File(filePath).read.full { (span: Swift.Span<Byte>) in
                var copy: [Byte] = []
                let count = Swift.min(span.count, Self.leading)
                copy.reserveCapacity(count)
                for index in span.indices.prefix(count) {
                    copy.append(span[index])
                }
                return copy
            }
        } catch {
            return false
        }
        let marker = [Byte](self.attribution.utf8)
        guard !marker.isEmpty else { return false }
        return head.firstRange(of: marker) != nil
    }
}
