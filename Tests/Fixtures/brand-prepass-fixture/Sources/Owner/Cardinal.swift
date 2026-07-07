// swift-format-ignore-file: AllPublicDeclarationsHaveDocumentation

// REASON: Tests/Fixtures/brand-prepass-fixture — synthetic consumer source is deliberately
// undocumented; its exact syntactic shape (a public "Cardinal" type declaring "rawValue") is
// what "brand owner run self-suppresses across files" (Lint.Run Tests.swift) exercises. Per
// rule-exemptions' self-referential fixture shape — shield, don't fix.
public struct Cardinal {
    public let rawValue: UInt
}
