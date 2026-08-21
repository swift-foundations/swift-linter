internal import Environment
public import File_System
internal import JSON

extension Lint.Fix.Scope.Manifest {

    public enum Channel {}
}

extension Lint.Fix.Scope.Manifest.Channel {

    public static let variable: Swift.String = "SWIFT_LINTER_FIX_MANIFEST"

    public static func value(_ path: File.Path) -> Swift.String {
        JSON.string(path.string).jsonString()
    }

    public static func read() throws(Error) -> File.Path? {
        guard let raw: Swift.String = Environment.read(Self.variable) else {
            return nil
        }
        return try resolve(raw)
    }

    internal static func resolve(_ raw: Swift.String) throws(Error) -> File.Path {
        let parsed: JSON
        do throws(JSON.Error) {
            parsed = try JSON.parse(raw)
        } catch {
            throw .unparseable(value: raw, description: "\(error)")
        }
        guard parsed.isString else {
            throw .unparseable(value: raw, description: "expected a JSON string")
        }
        let string = Swift.String(parsed)
        do throws(Paths.Path.Error) {
            return try File.Path(string)
        } catch {
            throw .invalid(path: string, description: "\(error)")
        }
    }
}
