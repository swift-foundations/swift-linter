import Testing

@testable import Linter_Core

extension Lint.Fix.Exclusion.Channel {
    @Suite struct Test {}
}

extension Lint.Fix.Exclusion.Channel.Test {
    @Test
    func `canonical rule IDs round trip through the channel`() throws(Lint.Fix.Exclusion.Channel
        .Error)
    {
        let rules: Set<Lint.Rule.ID> = [
            "shadowed standard name",
            "loop idiom",
        ]

        let decoded = try Lint.Fix.Exclusion.Channel.resolve(
            Lint.Fix.Exclusion.Channel.value(rules)
        )

        #expect(decoded == rules)
    }

    @Test
    func `duplicate IDs collapse and unknown IDs remain transportable`() throws(Lint.Fix.Exclusion
        .Channel.Error)
    {
        let decoded = try Lint.Fix.Exclusion.Channel.resolve(
            "[\"loop idiom\",\"loop idiom\",\"not installed here\"]"
        )

        #expect(decoded == ["loop idiom", "not installed here"])
    }

    @Test
    func `malformed exclusion channel fails loud`() {
        do throws(Lint.Fix.Exclusion.Channel.Error) {
            _ = try Lint.Fix.Exclusion.Channel.resolve("not-json")
            Issue.record("a malformed exclusion channel must throw")
        } catch {
            switch error {
            case .unparseable:
                break
            }
        }
    }
}
