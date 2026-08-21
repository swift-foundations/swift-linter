import Linter_Primitives
import Testing

@testable import Linter_Core

extension Lint.File.Single.Classifier {
    @Suite
    struct Test {}
}

extension Lint.File.Single.Classifier.Test {

    private func isEvalFallback(_ classification: Lint.File.Single.Classification) -> Swift.Bool {
        if case .evalFallback = classification { return true }
        return false
    }

    private func excluded(
        _ classification: Lint.File.Single.Classification
    ) -> (bundle: Lint.Rule.Bundle.Baked, disabled: Swift.Set<Lint.Rule.ID>)? {
        if case .fastPathStandardBundleExcluding(let bundle, let disabled) = classification {
            return (bundle: bundle, disabled: disabled)
        }
        return nil
    }

    @Test
    func `Bare primitives bundle in a trailing closure is the fast path`() {
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives
            }
            """
        #expect(
            Lint.File.Single.Classifier.classify(source: source)
                == .fastPathStandardBundle(bundle: .primitives)
        )
    }

    @Test
    func `Bare primitives bundle in a rules-labelled closure is the fast path`() {
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ], rules: {
                Lint.Rule.Bundle.primitives
            })
            """
        #expect(
            Lint.File.Single.Classifier.classify(source: source)
                == .fastPathStandardBundle(bundle: .primitives)
        )
    }

    @Test
    func `Excluding with string-literal IDs is fast path with exact exclusions`() {

        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives.excluding(rules: [
                    "raw value access",
                    "chained rawvalue access",
                    "int public parameter",
                    "pointer advanced by",
                ])
            }
            """
        let expected: Swift.Set<Lint.Rule.ID> = [
            "raw value access", "chained rawvalue access", "int public parameter",
            "pointer advanced by",
        ]
        #expect(
            excluded(Lint.File.Single.Classifier.classify(source: source))?.disabled == expected
        )
    }

    @Test
    func `Excluding with .id-accessor IDs is fast path with exact exclusions`() {

        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules
            import Primitives_Linter_Rule_RawValue

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives.excluding(rules: [
                    Lint.Rule.`raw value access`.id,
                    Lint.Rule.`chained rawvalue access`.id,
                    Lint.Rule.`unchecked call site`.id,
                ])
            }
            """
        let expected: Swift.Set<Lint.Rule.ID> = [
            "raw value access", "chained rawvalue access", "unchecked call site",
        ]
        #expect(
            excluded(Lint.File.Single.Classifier.classify(source: source))?.disabled == expected
        )
    }

    @Test
    func `Excluding with mixed string and .id forms extracts both exactly`() {
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives.excluding(rules: [
                    "raw value access",
                    Lint.Rule.`pointer advanced by`.id,
                ])
            }
            """
        let expected: Swift.Set<Lint.Rule.ID> = ["raw value access", "pointer advanced by"]
        #expect(
            excluded(Lint.File.Single.Classifier.classify(source: source))?.disabled == expected
        )
    }

    @Test
    func `Excluding with an unreadable element falls back to eval (never guess)`() {

        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives.excluding(rules: [
                    "raw value access",
                    someComputedRuleID(),
                ])
            }
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }

    @Test
    func `Excluding with an empty list falls back to eval`() {
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives.excluding(rules: [])
            }
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }

    @Test
    func `Inline custom rule plus enable falls back to eval`() {

        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules
            import SwiftSyntax

            extension Lint.Rule {
                static let `sli public carrier import` = Lint.Rule(
                    id: "sli public carrier import",
                    default: .warning,
                    findings: { source, severity in [] }
                )
            }

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives.excluding(rules: [Lint.Rule.`int public parameter`.id])
                Lint.Rule.Configuration.enable(.`sli public carrier import`)
            }
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }

    @Test
    func `Bare standards bundle is the fast path with the standards token`() {

        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Standards_Rules

            Lint.run(dependencies: [
                .package(url: "https://github.com/swift-standards/swift-standards-linter-rules.git", branch: "main", products: ["Linter Standards Rules"])
            ]) {
                Lint.Rule.Bundle.standards
            }
            """
        #expect(
            Lint.File.Single.Classifier.classify(source: source)
                == .fastPathStandardBundle(bundle: .standards)
        )
    }

    @Test
    func `Bare institute bundle is the fast path with the institute token`() {
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Institute_Rules

            Lint.run(dependencies: [
                .package(path: "../../swift-foundations/swift-institute-linter-rules", products: ["Linter Institute Rules"])
            ]) {
                Lint.Rule.Bundle.institute
            }
            """
        #expect(
            Lint.File.Single.Classifier.classify(source: source)
                == .fastPathStandardBundle(bundle: .institute)
        )
    }

    @Test
    func `Standards bundle with exclusions carries the standards token`() {
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Standards_Rules

            Lint.run(dependencies: [
                .package(url: "https://github.com/swift-standards/swift-standards-linter-rules.git", branch: "main", products: ["Linter Standards Rules"])
            ]) {
                Lint.Rule.Bundle.standards.excluding(rules: [
                    "raw value access",
                ])
            }
            """
        let result = excluded(Lint.File.Single.Classifier.classify(source: source))
        #expect(result?.bundle == .standards)
        #expect(result?.disabled == ["raw value access"])
    }

    @Test
    func `Institute bundle with exclusions carries the institute token`() {
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Institute_Rules

            Lint.run(dependencies: [
                .package(path: "../../swift-foundations/swift-institute-linter-rules", products: ["Linter Institute Rules"])
            ]) {
                Lint.Rule.Bundle.institute.excluding(rules: [
                    Lint.Rule.`raw value access`.id,
                ])
            }
            """
        let result = excluded(Lint.File.Single.Classifier.classify(source: source))
        #expect(result?.bundle == .institute)
        #expect(result?.disabled == ["raw value access"])
    }

    @Test
    func `Non-baked bundle falls back to eval`() {

        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Rules

            Lint.run(dependencies: [
                .package(path: ".", products: ["Linter Rules"])
            ]) {
                Lint.Rule.Bundle.universal
            }
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }

    @Test
    func `Non-baked bundle with exclusions falls back to eval`() {
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Rules

            Lint.run(dependencies: [
                .package(path: ".", products: ["Linter Rules"])
            ]) {
                Lint.Rule.Bundle.universal.excluding(rules: ["raw value access"])
            }
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }

    @Test
    func `Parent inheritance directive falls back to eval`() {

        let source = """
            // swift-linter-tools-version: 0.1
            // parent: https://github.com/swift-primitives/swift-primitives-linter-rules.git
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives
            }
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }

    @Test
    func `A non-directive parent substring stays on the fast path`() {

        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives  // not a // parent: directive, just prose
            }
            """
        #expect(
            Lint.File.Single.Classifier.classify(source: source)
                == .fastPathStandardBundle(bundle: .primitives)
        )
    }

    @Test
    func `Source without a run call falls back to eval`() {
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            let manifest: Lint.Manifest = Lint.Manifest()
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }

    @Test
    func `Two-statement bare closure falls back to eval`() {

        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives
                Lint.Rule.Configuration.disable(.`raw value access`)
            }
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }
}
