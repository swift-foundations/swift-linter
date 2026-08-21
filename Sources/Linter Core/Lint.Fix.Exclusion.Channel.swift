internal import Environment
internal import JSON

extension Lint.Fix.Exclusion {

    public enum Channel {}
}

extension Lint.Fix.Exclusion.Channel {

    public static let variable: Swift.String = "SWIFT_LINTER_FIX_EXCLUDING_RULES"

    public static func value(_ rules: Set<Lint.Rule.ID>) -> Swift.String {
        JSON.array(rules.map { .string($0.underlying) }).jsonString()
    }

    public static func read() throws(Error) -> Set<Lint.Rule.ID>? {
        guard let raw: Swift.String = Environment.read(Self.variable) else {
            return nil
        }
        return try resolve(raw)
    }

    internal static func resolve(_ raw: Swift.String) throws(Error) -> Set<Lint.Rule.ID> {
        let parsed: JSON
        do throws(JSON.Error) {
            parsed = try JSON.parse(raw)
        } catch {
            throw .unparseable(value: raw, description: "\(error)")
        }

        let identifiers: [Swift.String]
        do throws(JSON.Error) {
            identifiers = try [Swift.String](json: parsed)
        } catch {
            throw .unparseable(value: raw, description: "\(error)")
        }

        return Set(identifiers.map { Lint.Rule.ID(_unchecked: $0) })
    }
}
