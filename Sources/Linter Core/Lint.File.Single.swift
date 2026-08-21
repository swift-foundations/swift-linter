internal import Environment
public import File_System
internal import SwiftParser
internal import SwiftSyntax

extension Lint.File {

    public enum Single: Swift.Sendable {}
}

extension Lint.File.Single {

    @inlinable
    public static func canonicalize(
        consumerRoot: Swift.String,
        currentWorkingDirectory: () -> Swift.String?
    ) -> Swift.String {
        if consumerRoot.isEmpty || consumerRoot == "." {
            return currentWorkingDirectory() ?? consumerRoot
        }
        return consumerRoot
    }

    internal static func contents(
        of path: File.Path
    ) throws(File.System.Read.Full.Error) -> Swift.String {

        let bytes: [Byte]
        do throws(Either<File.System.Read.Full.Error, Never>) {
            bytes = try File(path).read.full { (span: Swift.Span<Byte>) -> [Byte] in
                var array: [Byte] = []
                array.reserveCapacity(span.count)
                span.indices.forEach { array.append(span[$0]) }
                return array
            }
        } catch {
            throw error.value
        }
        return Swift.String(decoding: bytes, as: UTF8.self)
    }

    public static func dispatch(
        at consumerPackageRoot: File.Path,
        arguments: [Swift.String],
        nonce: Swift.String = ""
    ) throws(Self.Error) -> Swift.Int32 {
        let consumerLintSwiftPath: File.Path = consumerPackageRoot / "Lint.swift"

        let source: Swift.String
        do throws(File.System.Read.Full.Error) {
            source = try Self.contents(of: consumerLintSwiftPath)
        } catch {
            throw .readFailed(path: consumerLintSwiftPath, description: "\(error)")
        }

        guard Detection.hasMagicComment(in: source) else {
            throw .missingToolsVersion(path: consumerLintSwiftPath)
        }

        let parsed: SourceFileSyntax = Parser.parse(source: source)

        if let runnerBinary: Swift.String = Environment.read("SWIFT_LINTER_RUNNER") {
            switch Self.Classifier.classify(source: source, parsed: parsed) {
            case .fastPathStandardBundle(let bundle):
                return try Runner.run(
                    binary: runnerBinary,
                    consumerPackageRoot: consumerPackageRoot,
                    arguments: arguments,
                    selection: nil,
                    bundle: bundle,
                    nonce: nonce
                )

            case .fastPathStandardBundleExcluding(let bundle, let disabled):

                return try Runner.run(
                    binary: runnerBinary,
                    consumerPackageRoot: consumerPackageRoot,
                    arguments: arguments,
                    selection: Lint.Manifest(disabled: disabled),
                    bundle: bundle,
                    nonce: nonce
                )

            case .evalFallback:
                break
            }
        }

        return try Eval.run(
            consumerPackageRoot: consumerPackageRoot,
            consumerLintSwiftPath: consumerLintSwiftPath,
            source: source,
            parsed: parsed,
            arguments: arguments,
            nonce: nonce
        )
    }

    public static func configuration(
        parentOf registry: [Lint.Rule.ID: Lint.Rule]
    ) throws(Channel.Error) -> Lint.Configuration? {
        guard let manifest: Lint.Manifest = try Channel.parent.read() else {
            return nil
        }
        return Lint.Configuration.lift(manifest: manifest, registry: registry)
    }
}
