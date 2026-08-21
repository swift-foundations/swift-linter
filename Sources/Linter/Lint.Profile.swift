internal import File_System
internal import JSON
public import Linter_Core

extension Lint {
    public struct Profile: Sendable {
        public static let schema = 1

        public let revision: Swift.String
        public let bundle: Lint.Rule.Bundle.Baked
        public let rules: [Lint.Rule.ID]

        public init(
            revision: Swift.String,
            bundle: Lint.Rule.Bundle.Baked,
            rules: [Lint.Rule.ID]
        ) throws(Error) {
            guard !revision.isEmpty else { throw .malformed("empty revision") }
            guard !rules.isEmpty else { throw .rules("zero rules") }
            guard Set(rules).count == rules.count else { throw .rules("duplicate rules") }
            self.revision = revision
            self.bundle = bundle
            self.rules = rules
        }
    }
}

extension Lint.Profile {
    public static func read(at path: Swift.String) throws(Error) -> Self {
        let file: File.Path
        do throws(File.Path.Error) { file = try .init(path) } catch { throw .path("\(error)") }
        let contents: Swift.String
        do throws(Either<File.System.Read.Full.Error, Never>) {
            contents = try File(file).read.full { bytes in
                var storage: [Byte] = []
                storage.reserveCapacity(bytes.count)
                for index in bytes.indices { storage.append(bytes[index]) }
                return Swift.String(decoding: storage, as: Swift.UTF8.self)
            }
        } catch { throw .read("\(error)") }
        let document: JSON
        do throws(JSON.Error) { document = try JSON.parse(contents) } catch {
            throw .malformed("\(error)")
        }
        guard let object = document.dictionary else { throw .malformed("expected object") }
        guard let schema = object["schema"], let revision = object["revision"],
            let bundle = object["bundle"], let rules = object["rules"]
        else { throw .malformed("missing required field") }
        let decodedSchema: Swift.Int
        let decodedRevision: Swift.String
        let decodedBundle: Swift.String
        let decodedRules: [Swift.String]
        do throws(JSON.Error) {
            decodedSchema = try Swift.Int(json: schema)
            decodedRevision = try Swift.String(json: revision)
            decodedBundle = try Swift.String(json: bundle)
            decodedRules = try [Swift.String](json: rules)
        } catch { throw .malformed("\(error)") }
        guard decodedSchema == Self.schema else { throw .schema(decodedSchema) }
        guard let baked = Lint.Rule.Bundle.Baked(rawValue: decodedBundle) else {
            throw .bundle(decodedBundle)
        }
        return try Self(
            revision: decodedRevision,
            bundle: baked,
            rules: decodedRules.map(Lint.Rule.ID.init)
        )
    }

    public func select(
        from bundle: [Lint.Rule.Configuration]
    ) throws(Error) -> [Lint.Rule.Configuration] {
        var available: [Lint.Rule.ID: Lint.Rule.Configuration] = [:]
        for entry in bundle {
            guard available[entry.rule.id] == nil else {
                throw .rules("duplicate baked rule \(entry.rule.id.underlying)")
            }
            available[entry.rule.id] = entry
        }
        return try rules.map { rule in
            guard let configuration = available[rule] else {
                throw .rules("unknown rule \(rule.underlying)")
            }
            return configuration
        }
    }
}
