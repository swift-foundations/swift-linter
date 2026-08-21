internal import File_System
internal import Package_Manager

extension Lint.Fix.Scope {

    public enum Manifest {}
}

extension Lint.Fix.Scope.Manifest {

    internal static func evaluates(_ text: Swift.String) -> Swift.Bool {
        let key = Swift.String(
            Swift.UInt64.random(in: Swift.UInt64.min...Swift.UInt64.max),
            radix: 16
        )
        let directory: File.Path
        do throws(File.Path.Error) {
            directory = try File.Path.Temporary.deterministic(
                prefix: "swift-linter-fix-manifest-verify-",
                key: key,
                suffix: ""
            )
        } catch {
            return false
        }
        defer {
            do throws(File.System.Delete.Error) {
                try File.System.Delete.delete(at: directory, recursive: true)
            } catch {

            }
        }
        do throws(File.System.Create.Directory.Error) {
            try File.Directory(directory).create.recursive()
        } catch {
            return false
        }
        do throws(File.System.Write.Atomic.Error) {
            try File(directory / "Package.swift").write.atomic(text)
        } catch {
            return false
        }
        do throws(Package.Manager.Error) {
            _ = try Package.Manager().evaluation(at: directory.string)
        } catch {
            return false
        }
        return true
    }
}
