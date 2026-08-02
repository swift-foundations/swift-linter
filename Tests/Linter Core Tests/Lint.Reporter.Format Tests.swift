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

import Environment
import JSON
import Linter
import Testing

extension Lint.Reporter.Format {
    @Suite(.serialized)
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

extension Lint.Reporter.Format.Test {
    fileprivate static func withVariable(_ value: Swift.String?, body: () -> Swift.Void) {
        if let value {
            // swift-format-ignore: NeverUseForceTry
            try! Environment.write(Lint.Reporter.Format.Channel.variable, to: value)
        } else {
            // swift-format-ignore: NeverUseForceTry
            try! Environment.write.unset(Lint.Reporter.Format.Channel.variable)
        }
        defer {
            // swift-format-ignore: NeverUseForceTry
            try! Environment.write.unset(Lint.Reporter.Format.Channel.variable)
        }
        body()
    }

    fileprivate static func finding() -> Lint.Finding {
        Lint.Finding(
            record: Diagnostic.Record(
                location: Source.Location(
                    fileID: "Module/Foo.swift",
                    filePath: "Sources/Foo.swift",
                    line: 10,
                    column: 5
                ),
                severity: .warning,
                identifier: "fixture rule",
                message: "fixture message"
            )
        )
    }
}

extension Lint.Reporter.Format.Test.Integration {
    @Test
    func `Unset channel preserves text compatibility`() {
        Lint.Reporter.Format.Test.withVariable(nil) {
            // swift-format-ignore: NeverUseForceTry
            #expect(try! Lint.Reporter.Format.Channel.read() == .text)
        }
    }

    @Test
    func `Every explicit format round trips through the channel`() {
        for format in Lint.Reporter.Format.allCases {
            Lint.Reporter.Format.Test.withVariable(
                Lint.Reporter.Format.Channel.value(format)
            ) {
                // swift-format-ignore: NeverUseForceTry
                #expect(try! Lint.Reporter.Format.Channel.read() == format)
            }
        }
    }
}

extension Lint.Reporter.Format.Test.`Edge Case` {
    @Test
    func `Corrupt channel throws instead of silently substituting text`() {
        Lint.Reporter.Format.Test.withVariable("checkstyle") {
            #expect(
                throws: Lint.Reporter.Format.Channel.Error.invalid(value: "checkstyle")
            ) {
                try Lint.Reporter.Format.Channel.read()
            }
        }
    }

    @Test
    func `Empty SARIF selection remains a valid document with no results`() throws(JSON.Error) {
        let report = Lint.Reporter.Format.sarif.report(for: [])
        let document = try JSON.parse(report)
        #expect(document.runs[0].results.array?.isEmpty == true)
    }
}

extension Lint.Reporter.Format.Test.Unit {
    @Test
    func `Explicit text selection preserves the canonical text report`() {
        let findings = [Lint.Reporter.Format.Test.finding()]
        let selected = Lint.Reporter.Format.text.report(for: findings)
        #expect(selected == Lint.Reporter.Text.report(for: findings))
        #expect(selected.hasPrefix("Sources/Foo.swift:10:5: warning: fixture rule:"))
    }

    @Test
    func `SARIF selection produces one structured result per finding`() throws(JSON.Error) {
        let report = Lint.Reporter.Format.sarif.report(
            for: [Lint.Reporter.Format.Test.finding()]
        )
        let document = try JSON.parse(report)
        let results = document.runs[0].results.array
        #expect(Swift.String(document.version) == "2.1.0")
        #expect(results?.count == 1)
        #expect(Swift.String(results?[0].ruleId) == "fixture rule")
        #expect(Swift.String(results?[0].level) == "warning")
        #expect(Swift.String(results?[0].message.text) == "fixture message")
    }
}
