import Linter_Primitives
import Linter_Reporter_Text
import Testing

@Suite
struct `Run summary line` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
}

extension `Run summary line`.Unit {
    @Test
    func `Clean bare run prints package, active rules, files, zero violations, zero findings`() {
        let line = Lint.Reporter.Text.Summary.line(
            package: "swift-pair-primitives",
            activeRules: 90,
            excludedRules: 0,
            filesLinted: 48,
            violations: 0,
            findings: 0
        )
        #expect(
            line
                == "swift-pair-primitives · 90 active rules · 48 files linted · 0 violations · 0 findings"
        )
    }

    @Test
    func `Overlay exclusion case annotates the excluded count`() {

        let line = Lint.Reporter.Text.Summary.line(
            package: "swift-cardinal-primitives",
            activeRules: 83,
            excludedRules: 7,
            filesLinted: 31,
            violations: 2,
            findings: 2
        )
        #expect(
            line
                == "swift-cardinal-primitives · 83 active rules (−7 excluded) · 31 files linted · 2 violations · 2 findings"
        )
    }

    @Test
    func `Singular file, violation, and finding forms`() {
        let line = Lint.Reporter.Text.Summary.line(
            package: "pkg",
            activeRules: 1,
            excludedRules: 0,
            filesLinted: 1,
            violations: 1,
            findings: 1
        )
        #expect(line == "pkg · 1 active rules · 1 file linted · 1 violation · 1 finding")
    }

    @Test
    func `Zero-violation run still composes a full summary (never silent)`() {
        let line = Lint.Reporter.Text.Summary.line(
            package: "pkg",
            activeRules: 90,
            excludedRules: 0,
            filesLinted: 0,
            violations: 0,
            findings: 0
        )
        #expect(line == "pkg · 90 active rules · 0 files linted · 0 violations · 0 findings")
    }

    @Test
    func `Findings count diverges from violations when note or remark findings exist`() {

        let line = Lint.Reporter.Text.Summary.line(
            package: "swift-posix",
            activeRules: 40,
            excludedRules: 0,
            filesLinted: 12,
            violations: 3,
            findings: 9
        )
        #expect(
            line == "swift-posix · 40 active rules · 12 files linted · 3 violations · 9 findings"
        )
    }
}
