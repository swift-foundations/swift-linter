import Linter_Primitives
import Linter_Reporter_SARIF
import Linter_Reporter_Text
import Testing

extension Lint.Reporter {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
        @Suite struct Text {}
        @Suite struct SARIF {}
    }
}

extension Lint.Reporter.Test {

    fileprivate static func fixture(
        visibility: Lint.Visibility?
    ) -> Lint.Finding {
        let record = Diagnostic.Record(
            location: Source.Location(
                fileID: "Module/Foo.swift",
                filePath: "/tmp/Foo.swift",
                line: 10,
                column: 5
            ),
            severity: .warning,
            identifier: "fixture rule",
            message: "fixture message"
        )
        return Lint.Finding(record: record, visibility: visibility)
    }
}

extension Lint.Reporter.Test.Text {
    @Test
    func `nil visibility omits the bracketed suffix`() {
        let finding = Lint.Reporter.Test.fixture(visibility: nil)
        let line = Lint.Reporter.Text.line(for: finding)
        #expect(!line.contains("[visibility:"))

        #expect(line.hasPrefix("/tmp/Foo.swift:10:5: warning: fixture rule: fixture message"))
    }

    @Test
    func `private visibility appends the bracketed suffix`() {
        let finding = Lint.Reporter.Test.fixture(visibility: .private)
        let line = Lint.Reporter.Text.line(for: finding)
        #expect(line.hasSuffix(" [visibility: private]"))
    }

    @Test
    func `each visibility case round-trips via its raw value`() {
        for visibility in Lint.Visibility.allCases {
            let finding = Lint.Reporter.Test.fixture(visibility: visibility)
            let line = Lint.Reporter.Text.line(for: finding)
            #expect(line.hasSuffix(" [visibility: \(visibility.rawValue)]"))
        }
    }
}

extension Lint.Reporter.Test.SARIF {
    @Test
    func `nil visibility omits the properties field`() {
        let finding = Lint.Reporter.Test.fixture(visibility: nil)
        let report = Lint.Reporter.SARIF.report(for: [finding])
        #expect(!report.contains("\"visibility\""))

        #expect(report.contains("\"ruleId\""))
    }

    @Test
    func `private visibility appears under properties`() {
        let finding = Lint.Reporter.Test.fixture(visibility: .private)
        let report = Lint.Reporter.SARIF.report(for: [finding])
        #expect(report.contains("\"properties\""))
        #expect(report.contains("\"visibility\""))
        #expect(report.contains("\"private\""))
    }

    @Test
    func `each visibility case is emitted by its raw value`() {
        for visibility in Lint.Visibility.allCases {
            let finding = Lint.Reporter.Test.fixture(visibility: visibility)
            let report = Lint.Reporter.SARIF.report(for: [finding])
            #expect(report.contains("\"\(visibility.rawValue)\""))
        }
    }
}
