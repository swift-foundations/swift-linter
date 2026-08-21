internal import Environment
public import File_System
internal import JSON

extension Lint.Fix.Scope {

    public enum Channel {}
}

extension Lint.Fix.Scope.Channel {

    public static let variable: Swift.String = "SWIFT_LINTER_FIX_TARGETS"

    public static func value(_ roots: [File.Path]) -> Swift.String {
        JSON.array(roots.map { .string($0.string) }).jsonString()
    }

    public static func read() throws(Error) -> [File.Path]? {
        guard let raw: Swift.String = Environment.read(Self.variable) else {
            return nil
        }
        return try resolve(raw)
    }

    internal static func resolve(_ raw: Swift.String) throws(Error) -> [File.Path] {
        let parsed: JSON
        do throws(JSON.Error) {
            parsed = try JSON.parse(raw)
        } catch {
            throw .unparseable(value: raw, description: "\(error)")
        }

        let strings: [Swift.String]
        do throws(JSON.Error) {
            strings = try [Swift.String](json: parsed)
        } catch {
            throw .unparseable(value: raw, description: "\(error)")
        }

        var roots = [File.Path]()
        roots.reserveCapacity(strings.count)
        for string in strings {
            do throws(Paths.Path.Error) {
                roots.append(try File.Path(string))
            } catch {
                throw .invalid(path: string, description: "\(error)")
            }
        }
        return roots
    }
}
