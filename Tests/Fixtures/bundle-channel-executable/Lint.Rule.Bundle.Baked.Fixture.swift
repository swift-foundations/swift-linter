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

import Linter

// A3 regression fixture for ``Lint/run(bundles:)``'s ``Lint/Rule/Bundle/Baked``
// dispatch: bakes THREE distinguishable rules, one per baked-bundle token, so
// a process test can prove a valid ``SWIFT_LINTER_BUNDLE`` token selects
// EXACTLY its own bundle — never a different one, and never all three at
// once. Each rule fires unconditionally (mirrors `report format fixture`),
// so its identifier alone in the emitted findings/summary distinguishes
// which bundle actually ran.

extension Lint.Rule {
    fileprivate static let `bundle fixture primitives` = Lint.Rule(
        id: "bundle fixture primitives",
        default: .error,
        findings: { source, severity in
            [
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.file.fileID,
                        filePath: source.file.filePath,
                        line: 1,
                        column: 1
                    ),
                    severity: severity,
                    identifier: "bundle fixture primitives",
                    message: "primitives bundle fired"
                )
            ]
        }
    )

    fileprivate static let `bundle fixture standards` = Lint.Rule(
        id: "bundle fixture standards",
        default: .error,
        findings: { source, severity in
            [
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.file.fileID,
                        filePath: source.file.filePath,
                        line: 1,
                        column: 1
                    ),
                    severity: severity,
                    identifier: "bundle fixture standards",
                    message: "standards bundle fired"
                )
            ]
        }
    )

    fileprivate static let `bundle fixture institute` = Lint.Rule(
        id: "bundle fixture institute",
        default: .error,
        findings: { source, severity in
            [
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.file.fileID,
                        filePath: source.file.filePath,
                        line: 1,
                        column: 1
                    ),
                    severity: severity,
                    identifier: "bundle fixture institute",
                    message: "institute bundle fired"
                )
            ]
        }
    )
}

Lint.run(bundles: [
    .primitives: [.enable(.`bundle fixture primitives`)],
    .standards: [.enable(.`bundle fixture standards`)],
    .institute: [.enable(.`bundle fixture institute`)],
])
