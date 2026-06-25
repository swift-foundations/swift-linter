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

import Cardinal_Primitives
import Linter_Primitives
import Linter_Reporter_Text
import Testing

// MARK: - Lint.Reporter.Text.Summary.line(package:activeRules:excludedRules:filesLinted:violations:)
//
// The always-on run summary's pure formatter. The emitted line goes to STDERR
// (stdout stays the pure diagnostic stream — verified at the integration level
// by running the binary and checking the streams separately). These unit tests
// pin the field composition, including that the resolved active-rule field
// reflects an overlay/exclusion case.

@Suite
struct `Run summary line` {
    @Test
    func `Clean bare run prints package, active rules, files, zero violations`() {
        let line = Lint.Reporter.Text.Summary.line(
            package: "swift-pair-primitives",
            activeRules: 90,
            excludedRules: 0,
            filesLinted: 48,
            violations: 0
        )
        #expect(line == "swift-pair-primitives · 90 active rules · 48 files linted · 0 violations")
    }

    @Test
    func `Overlay exclusion case annotates the excluded count`() {
        // The resolved-set field reflects the runtime overlay: 83 active
        // (= 90 − 7) with the 7 excluded annotated.
        let line = Lint.Reporter.Text.Summary.line(
            package: "swift-cardinal-primitives",
            activeRules: 83,
            excludedRules: 7,
            filesLinted: 31,
            violations: 2
        )
        #expect(line == "swift-cardinal-primitives · 83 active rules (−7 excluded) · 31 files linted · 2 violations")
    }

    @Test
    func `Singular file and violation forms`() {
        let line = Lint.Reporter.Text.Summary.line(
            package: "pkg",
            activeRules: 1,
            excludedRules: 0,
            filesLinted: 1,
            violations: 1
        )
        #expect(line == "pkg · 1 active rules · 1 file linted · 1 violation")
    }

    @Test
    func `Zero-violation run still composes a full summary (never silent)`() {
        let line = Lint.Reporter.Text.Summary.line(
            package: "pkg",
            activeRules: 90,
            excludedRules: 0,
            filesLinted: 0,
            violations: 0
        )
        #expect(line == "pkg · 90 active rules · 0 files linted · 0 violations")
    }
}
