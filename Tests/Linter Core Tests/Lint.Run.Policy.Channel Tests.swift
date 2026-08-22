import Environment
import Testing

@testable import Linter_Core

extension Lint.Run.Policy.Channel {
    @Suite(.serialized)
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

extension Lint.Run.Policy.Channel.Test {
    private func withVariable(_ value: Swift.String?, body: () -> Swift.Void) {
        if let value {

            try! Environment.write(Lint.Run.Policy.Channel.variable, to: value)
        } else {

            try! Environment.write.unset(Lint.Run.Policy.Channel.variable)
        }
        defer {

            try! Environment.write.unset(Lint.Run.Policy.Channel.variable)
        }
        body()
    }

    @Test
    func `unset reads nil`() {
        withVariable(nil) {

            #expect(try! Lint.Run.Policy.Channel.read() == nil)
        }
    }

    @Test
    func `vocabulary round trips`() {
        for policy in Lint.Run.Policy.allCases {
            withVariable(policy.rawValue) {

                #expect(try! Lint.Run.Policy.Channel.read() == policy)
            }
        }
    }

    @Test
    func `invalid value throws`() {
        withVariable("warnings-as-errors") {
            #expect(throws: Lint.Run.Policy.Channel.Error.invalid(value: "warnings-as-errors")) {
                try Lint.Run.Policy.Channel.read()
            }
        }
    }
}
