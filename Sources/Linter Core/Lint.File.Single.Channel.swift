internal import Environment
public import File_System
internal import JSON

extension Lint.File.Single {

    public struct Channel: Swift.Sendable {

        public let variable: Swift.String

        public let basename: Swift.String

        @inlinable
        public init(variable: Swift.String, basename: Swift.String) {
            self.variable = variable
            self.basename = basename
        }
    }
}

extension Lint.File.Single.Channel {

    public static let selection = Self(
        variable: "SWIFT_LINTER_SELECTION_MANIFEST",
        basename: "selection-manifest"
    )

    public static let parent = Self(
        variable: "SWIFT_LINTER_PARENT_MANIFEST",
        basename: "parent-manifest"
    )
}

extension Lint.File.Single.Channel {

    internal func path(
        consumerPackageRoot: File.Path,
        nonce: Swift.String
    ) throws(Paths.Path.Error) -> File.Path {
        let name: Swift.String = nonce.isEmpty ? "\(basename).json" : "\(basename)-\(nonce).json"

        let trailing: File.Path = try File.Path(name)
        return Lint.File.Single.State.directory(consumerPackageRoot: consumerPackageRoot).appending(
            trailing
        )
    }

    public func write(
        _ manifest: Lint.Manifest,
        consumerPackageRoot: File.Path,
        nonce: Swift.String
    ) throws(Error) -> File.Path {
        do throws(Lint.File.Single.State.Error) {
            _ = try Lint.File.Single.State.create(consumerPackageRoot: consumerPackageRoot)
        } catch {
            throw .writeFailed(variable: variable, description: "create state directory: \(error)")
        }
        let target: File.Path
        do throws(Paths.Path.Error) {
            target = try self.path(consumerPackageRoot: consumerPackageRoot, nonce: nonce)
        } catch {
            throw .writeFailed(variable: variable, description: "compose manifest path: \(error)")
        }
        let json: Swift.String = Lint.Manifest.serialize(manifest).jsonString()
        do throws(File.System.Write.Atomic.Error) {
            try File(target).write.atomic(json)
        } catch {
            throw .writeFailed(variable: variable, description: "write \(target.string): \(error)")
        }
        return target
    }

    public func read() throws(Error) -> Lint.Manifest? {
        guard let raw: Swift.String = Environment.read(variable) else {
            return nil
        }
        return try self.resolve(raw: raw)
    }

    internal func resolve(raw: Swift.String) throws(Error) -> Lint.Manifest {
        let path: File.Path
        do throws(Paths.Path.Error) {
            path = try File.Path(raw)
        } catch {
            throw .invalidPath(variable: variable, raw: raw, description: "\(error)")
        }
        let source: Swift.String
        do throws(File.System.Read.Full.Error) {
            source = try Lint.File.Single.contents(of: path)
        } catch {
            throw .unreadable(variable: variable, path: path, description: "\(error)")
        }
        let parsed: JSON
        do throws(JSON.Error) {
            parsed = try JSON.parse(source)
        } catch {
            throw .unparseable(variable: variable, path: path, description: "\(error)")
        }
        let manifest: Lint.Manifest
        do throws(JSON.Error) {
            manifest = try Lint.Manifest.deserialize(parsed)
        } catch {
            throw .unparseable(variable: variable, path: path, description: "\(error)")
        }
        return manifest
    }
}
