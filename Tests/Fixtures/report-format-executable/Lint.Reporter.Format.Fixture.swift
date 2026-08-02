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

extension Lint.Rule {
    fileprivate static let `report format fixture` = Lint.Rule(
        id: "report format fixture",
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
                    identifier: "report format fixture",
                    message: "fixture rule fired"
                )
            ]
        }
    )
}

Lint.run(bundles: [
    .primitives: [.enable(.`report format fixture`)]
])
