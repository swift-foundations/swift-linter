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

internal import Linter_Primitives

extension Lint.Provenance {
    /// The central register of declared vendored forks.
    ///
    /// This is the ONLY place fork provenance is declared. Entries are
    /// added, narrowed, and removed through pull requests to
    /// swift-foundations/swift-linter — a consumer cannot declare, widen,
    /// or edit one from its own configuration, and no package-local file
    /// participates. Each entry names the fork's package identity, the
    /// asserted upstream ancestry (repository + fork-point commit), the
    /// literal upstream attribution its vendored files carry, and the
    /// explicit vendored scope. See ``Lint/Provenance`` for the
    /// three-condition exemption predicate an entry feeds
    /// (swift-foundations/swift-linter#45).
    public enum Register {}
}

extension Lint.Provenance.Register {
    /// Every declared fork.
    ///
    /// swift-certificate-verification: true fork of
    /// apple/swift-certificates at 1.18.0 — stated in that repository's
    /// `Package.swift` header, `NOTICE.txt`, and `README.md`, with every
    /// vendored file keeping its upstream Apache-2.0 header. The vendored
    /// scope mirrors the provenance analysis recorded on
    /// swift-foundations/swift-linter#45 and the repository's PR #9:
    /// everything under `Sources` is the fork (including files patched
    /// mechanically for build compatibility), plus the enumerated
    /// verbatim/near-verbatim test lifts. Institute-authored additions
    /// (e.g. `Tests/X509Tests/TestPKI.swift`, and the DSL entry points
    /// added to `ExtensionsBuilder.swift` / `DNBuilder.swift`) are NOT
    /// enumerated and stay fully linted; a newly added file defaults to
    /// linted unless it lands under a vendored `Sources` directory —
    /// which is a vendoring decision this register owns.
    public static let declared: [Lint.Provenance.Fork] = [
        Lint.Provenance.Fork(
            package: "swift-certificate-verification",
            upstream: Lint.Provenance.Fork.Upstream(
                repository: "apple/swift-certificates",
                commit: "24ccdeeeed4dfaae7955fcac9dbf5489ed4f1a25"
            ),
            attribution: "Apple Inc. and the SwiftCertificates project authors",
            vendored: [
                .directory("Sources/X509"),
                .directory("Sources/_CertificateInternals"),
                .file("Tests/X509Tests/RFC5280Policy Tests.swift"),
                .file("Tests/X509Tests/Verifier Tests.swift"),
                .file("Tests/X509Tests/CertificateStore Tests.swift"),
                .file("Tests/X509Tests/CommonName.swift"),
                .file("Tests/X509Tests/CountryName.swift"),
                .file("Tests/X509Tests/DomainComponent.swift"),
                .file("Tests/X509Tests/EmailAddress.swift"),
                .file("Tests/X509Tests/LocalityName.swift"),
                .file("Tests/X509Tests/OrganizationName.swift"),
                .file("Tests/X509Tests/OrganizationalUnitName.swift"),
                .file("Tests/X509Tests/StateOrProvinceName.swift"),
                .file("Tests/X509Tests/StreetAddress.swift"),
                .file("Tests/X509Tests/Instant+TestSeconds.swift"),
                .file("Tests/X509Tests/Issuance.swift"),
                .file("Tests/X509Tests/Issuance Tests.swift"),
                .file("Tests/X509Tests/PublicKey+Crypto.swift"),
                .file("Tests/X509Tests/Verify+Crypto.swift"),
                .file("Tests/X509Tests/Certificate Tests.swift"),
                .file("Tests/X509Tests/Certificate.DER Tests.swift"),
                .file("Tests/X509Tests/Certificate.Signature Tests.swift"),
                .file("Tests/X509Tests/Certificate.Verify Tests.swift"),
                .file("Tests/X509Tests/DNSNames Tests.swift"),
                .file("Tests/X509Tests/DistinguishedName Tests.swift"),
                .file("Tests/X509Tests/ExtendedKeyUsage Tests.swift"),
                .file("Tests/X509Tests/GeneralName Tests.swift"),
                .file("Tests/X509Tests/IPAddress Tests.swift"),
                .file("Tests/X509Tests/Instant+TestSeconds Tests.swift"),
                .file("Tests/X509Tests/NameConstraints Tests.swift"),
                .file("Tests/X509Tests/PolicyBuilder Tests.swift"),
                .file("Tests/X509Tests/ServerIdentityPolicy Tests.swift"),
                .file("Tests/X509Tests/Time Tests.swift"),
                .file("Tests/X509Tests/Fixtures.swift"),
                .file("Tests/CertificateInternalsTests/TinyArray Tests.swift"),
            ]
        )
    ]
}
