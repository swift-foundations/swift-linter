internal import Environment

extension Lint.Fix.Mode {

    public enum Channel {}
}

extension Lint.Fix.Mode.Channel {

    public static let variable: Swift.String = "SWIFT_LINTER_FIX"

    public static func read() throws(Error) -> Lint.Fix.Mode? {
        guard let raw: Swift.String = Environment.read(Self.variable) else {
            return nil
        }
        guard let mode: Lint.Fix.Mode = Lint.Fix.Mode(rawValue: raw) else {
            throw .invalid(value: raw)
        }
        return mode
    }
}

extension Lint.Fix.Mode.Channel {

    public enum Error: Swift.Error, Hashable, Sendable {
        case invalid(value: Swift.String)
    }
}
