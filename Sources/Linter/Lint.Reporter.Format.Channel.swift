internal import Environment

extension Lint.Reporter.Format {

    public enum Channel {}
}

extension Lint.Reporter.Format.Channel {

    public static let variable: Swift.String = "SWIFT_LINTER_FORMAT"

    public static func value(_ format: Lint.Reporter.Format) -> Swift.String {

        format.rawValue
    }

    public static func read() throws(Error) -> Lint.Reporter.Format {
        guard let raw: Swift.String = Environment.read(Self.variable) else {
            return .text
        }
        guard let format: Lint.Reporter.Format = Lint.Reporter.Format(rawValue: raw) else {
            throw .invalid(value: raw)
        }
        return format
    }
}
