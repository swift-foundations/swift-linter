import Environment
import Testing

@testable import Linter_Core

extension Lint.Rule.Bundle.Baked.Channel {
    @Suite(.serialized)
    struct Test {}
}

extension Lint.Rule.Bundle.Baked.Channel.Test {
    private func withVariable(_ value: Swift.String?, body: () -> Swift.Void) {
        if let value {

            try! Environment.write(Lint.Rule.Bundle.Baked.Channel.variable, to: value)
        } else {

            try! Environment.write.unset(Lint.Rule.Bundle.Baked.Channel.variable)
        }
        defer {

            try! Environment.write.unset(Lint.Rule.Bundle.Baked.Channel.variable)
        }
        body()
    }

    @Test
    func `unset reads nil`() {
        withVariable(nil) {

            #expect(try! Lint.Rule.Bundle.Baked.Channel.read() == nil)
        }
    }

    @Test
    func `vocabulary round trips`() {
        for bundle in Lint.Rule.Bundle.Baked.allCases {
            withVariable(bundle.rawValue) {

                #expect(try! Lint.Rule.Bundle.Baked.Channel.read() == bundle)
            }
        }
    }

    @Test
    func `invalid value throws`() {
        withVariable("universal") {
            #expect(throws: Lint.Rule.Bundle.Baked.Channel.Error.invalid(value: "universal")) {
                try Lint.Rule.Bundle.Baked.Channel.read()
            }
        }
    }

    @Test
    func `expressions match accessors`() {
        #expect(Lint.Rule.Bundle.Baked.primitives.expression == "Lint.Rule.Bundle.primitives")
        #expect(Lint.Rule.Bundle.Baked.standards.expression == "Lint.Rule.Bundle.standards")
        #expect(Lint.Rule.Bundle.Baked.institute.expression == "Lint.Rule.Bundle.institute")
    }
}
