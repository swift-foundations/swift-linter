public import SPM_Standard
public import URI_Standard
public import URI_Standard_Library_Integration
@_exported public import Version_Primitives_Standard_Library_Integration

extension Package.Dependency {

    @inlinable
    public static func package(
        path: Swift.String,
        products: [Product.Name]
    ) -> Package.Dependency {
        let basename: Swift.String = path.split(separator: "/").last.map(Swift.String.init) ?? path
        return Package.Dependency(
            source: .path(path),
            name: Package.Name(_unchecked: basename),
            products: products
        )
    }

    @inlinable
    public static func package(
        url: Swift.String,
        _ range: Swift.Range<Version.Semantic>,
        products: [Product.Name]
    ) -> Package.Dependency {
        var name: Swift.String = url.split(separator: "/").last.map(Swift.String.init) ?? url
        if name.hasSuffix(".git") {
            name.removeLast(4)
        }
        let requirement: Package.Requirement = .range(Version.Range(range))
        return Package.Dependency(
            source: .url(URI(stringLiteral: url), requirement),
            name: Package.Name(_unchecked: name),
            products: products
        )
    }

    @inlinable
    public static func package(
        url: Swift.String,
        from version: Version.Semantic,
        products: [Product.Name]
    ) -> Package.Dependency {
        var name: Swift.String = url.split(separator: "/").last.map(Swift.String.init) ?? url
        if name.hasSuffix(".git") {
            name.removeLast(4)
        }
        return Package.Dependency(
            source: .url(URI(stringLiteral: url), .from(version)),
            name: Package.Name(_unchecked: name),
            products: products
        )
    }

    @inlinable
    public static func package(
        url: Swift.String,
        branch: Swift.String,
        products: [Product.Name]
    ) -> Package.Dependency {
        var name: Swift.String = url.split(separator: "/").last.map(Swift.String.init) ?? url
        if name.hasSuffix(".git") {
            name.removeLast(4)
        }
        return Package.Dependency(
            source: .url(URI(stringLiteral: url), .branch(branch)),
            name: Package.Name(_unchecked: name),
            products: products
        )
    }
}
