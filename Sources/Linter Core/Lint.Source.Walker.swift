public import File_System
public import Glob_Primitives
import Glob_Primitives_Standard_Library_Integration
public import Linter_Primitives

extension Lint.Source {

    public enum Walker {}
}

extension Lint.Source.Walker {

    public static let included: [Glob.Pattern] = ["**/*.swift"]

    public static let excluded: [Glob.Pattern] = [
        "**/.build/**",
        "**/.swiftpm/**",
        "**/.benchmarks/**",
        "**/DerivedData/**",
        "**/Carthage/**",
        "**/Pods/**",
        "**/*.docc/**",
    ]

    public static func paths(under root: File.Path) -> [Lint.Source.Path] {

        if root.components.last?.extension?.string == "swift" {
            return [Lint.Source.Path("")]
        }

        let directory = File.Directory(root)
        let files: [File]
        do throws(Glob.Error) {
            files = try directory.glob.files(
                include: included,
                excluding: excluded
            )
        } catch {
            return []
        }

        var nestedPackageRoots: [File.Path] = []
        for file in files {
            guard file.path.components.last?.string == "Package.swift",
                let parent = file.path.parent,
                parent != root
            else { continue }
            nestedPackageRoots.append(parent)
        }

        var results: [Lint.Source.Path] = []
        results.reserveCapacity(files.count)
        for file in files {
            if nestedPackageRoots.contains(where: { file.path.hasPrefix($0) }) {
                continue
            }
            guard let relative = file.path.relative(to: root) else {
                continue
            }
            results.append(Lint.Source.Path(relative.string))
        }
        return results.sorted(by: { $0.underlying < $1.underlying })
    }
}
