public import ArgumentParser
import Environment
import File_System
public import File_System_Core
import Kernel
import Linter
import Linter_Reporter_SARIF
import Linter_Reporter_Text
import Terminal_Primitives

#if os(Windows)
    import Windows_32_Kernel_Directory
    import Windows_32_Kernel_Terminal
#endif

extension Lint.Reporter.Format: ExpressibleByArgument {}
extension Lint.Run.Policy: ExpressibleByArgument {}

extension File.Path: @retroactive ExpressibleByArgument {

    public init?(argument: Swift.String) {
        do throws(Paths.Path.Error) {
            self = try File.Path(argument)
        } catch {
            return nil
        }
    }
}

extension Lint {
    @main
    struct CLI: ParsableCommand {
        @Argument(help: "Paths to lint (files or directories). Defaults to current directory.")
        var paths: [Swift.String] = ["."]

        @Option(
            name: .long,
            help:
                "Output format. Choices: text, sarif, or structured."
        )
        var format: Lint.Reporter.Format = .text

        @Option(
            name: .customLong("lint-swift-path"),
            help: "Path to Lint.swift. Defaults to <path>/Lint.swift if present."
        )
        var linter: File_System.File.Path?

        @Option(
            name: [.customLong("exit-policy"), .customLong("strict")],
            help: """
                Exit policy. Choices: advisory (exit 0 always), strict (exit non-zero when any \
                finding has severity:error). The legacy --strict flag is honored.
                """
        )
        var policy: Lint.Run.Policy = .advisory

    }
}

extension Lint.CLI {
    static let configuration = CommandConfiguration(
        commandName: "swift-linter",
        abstract: "SwiftSyntax-based AST linter for the swift-primitives ecosystem.",
        discussion: """
            Augments SwiftLint by hosting AST-shaped rules whose predicate cannot \
            be expressed as a regex on source text. The engine ships rule-pack-\
            agnostic — without an explicit configuration, zero rules fire.

            Three consumer shapes are detected at the package root, in priority \
            order: (1) a single-file `Lint.swift` with a `// swift-linter-tools-\
            version:` magic-comment header (Shape γ — recommended; declares \
            SwiftPM deps + rule activations in one file), (2) a `Lint/` nested \
            SwiftPM package (the prior recommended shape; consumers wire engine \
            + rule packs in its `Package.swift`), or (3) a legacy single-file \
            `Lint.swift` declaring `let manifest: Lint.Manifest` (inert post-\
            Phase-B.1 decouple). When none is present, the CLI runs with the \
            empty default Configuration.
            """
    )
}

extension Lint.CLI {

    #if !os(Windows)
        fileprivate typealias KernelWrite = ISO_9945.Kernel.IO.Write.Error
    #else
        fileprivate typealias KernelWrite = Windows.`32`.Kernel.IO.Write.Error
    #endif

    #if !os(Windows)
        fileprivate static func bytes(of text: Swift.String) -> [Byte] {
            text.utf8.map(Byte.init)
        }
    #else
        fileprivate static func bytes(of text: Swift.String) -> [Swift.UInt8] {
            Swift.Array(text.utf8)
        }
    #endif

    fileprivate static func currentWorkingDirectory() -> Swift.String? {
        let result: Swift.String?
        #if !os(Windows)
            do throws(ISO_9945.Kernel.Directory.Working.Error) {
                result = try Kernel.Directory.Working.withCurrentBytes {
                    (span: Swift.Span<UInt8>) -> Swift.String in
                    var bytes: [UInt8] = []
                    bytes.reserveCapacity(span.count)
                    span.indices.forEach { bytes.append(span[$0]) }
                    return Swift.String(decoding: bytes, as: UTF8.self)
                }
            } catch {
                result = nil
            }
        #else
            do throws(Windows.`32`.Kernel.Directory.Working.Error) {
                result = Swift.String(
                    decoding: try Windows.`32`.Kernel.Directory.Working.get(),
                    as: UTF16.self
                )
            } catch {
                result = nil
            }
        #endif
        return result
    }
}

extension Lint.CLI {

    func run() throws {

        let consumerRootString: Swift.String = Lint.File.Single.canonicalize(
            consumerRoot: paths.first ?? ".",
            currentWorkingDirectory: { Lint.CLI.currentWorkingDirectory() }
        )

        let consumerRoot: File_System.File.Path = try File_System.File.Path(consumerRootString)

        try Environment.write(
            Lint.Reporter.Format.Channel.variable,
            to: Lint.Reporter.Format.Channel.value(format)
        )

        if policy != .advisory {
            try Environment.write(Lint.Run.Policy.Channel.variable, to: policy.rawValue)
        }

        if Lint.File.Single.Detection.detect(at: consumerRoot) != nil {

            let runNonce: Swift.String = Swift.String(
                UInt64.random(in: UInt64.min...UInt64.max),
                radix: 16
            )
            let dispatchedExitCode: Swift.Int32
            do throws(Lint.File.Single.Error) {
                dispatchedExitCode = try Lint.File.Single.dispatch(
                    at: consumerRoot,
                    arguments: paths,
                    nonce: runNonce
                )
            } catch {
                do throws(KernelWrite) {
                    _ = try Terminal.Stream.stderr.write(
                        Lint.CLI.bytes(
                            of: "[swift-linter] error: single-file dispatch failed: \(error)\n"
                        )
                    )
                } catch {

                }
                throw ExitCode.failure
            }
            if dispatchedExitCode != 0 {
                throw ExitCode(dispatchedExitCode)
            }
            return
        }

        if let dispatchedExitCode = Lint.Driver.dispatch.nested(
            at: consumerRoot,
            arguments: paths,
            onDispatchError: { description in
                do throws(KernelWrite) {
                    _ = try Terminal.Stream.stderr.write(
                        Lint.CLI.bytes(
                            of: "[swift-linter] error: nested-package dispatch failed: "
                                + "\(description)\n"
                        )
                    )
                } catch {

                }
            }
        ) {
            if dispatchedExitCode != 0 {
                throw ExitCode(dispatchedExitCode)
            }
            return
        }

        let configuration: Lint.Configuration = resolveConfiguration(consumerRoot: consumerRoot)

        let typedPaths: [File_System.File.Path] = try paths.map {
            (raw: Swift.String) throws(Paths.Path.Error) in
            try File_System.File.Path(raw)
        }
        let outcome: Lint.Run.Outcome = try Lint.Run.run(
            paths: typedPaths,
            capturing: .all,
            configuration: configuration
        )
        switch format {
        case .structured:
            Lint.Reporter.Text.emit(
                text: Lint.Reporter.Structured.report(for: outcome) + "\n",
                to: Terminal.Stream.stdout.write
            )
        case .text, .sarif:
            emit(outcome.findings)
        }
        Lint.Reporter.Text.emit(
            summaryFor: consumerRoot.components.last?.string ?? ".",
            activeRules: configuration.rules.effective.entries.count,
            excludedRules: configuration.rules.effective.disabled.count,
            filesLinted: outcome.filesLinted,
            violations: outcome.violations.count,
            findings: outcome.findings.count,
            to: Terminal.Stream.stderr.write
        )
        if outcome.summary.unmeasuredObservations > 0 {
            throw ExitCode(2)
        }
        if policy.fails(for: outcome.findings) {
            throw ExitCode.failure
        }
    }

    fileprivate func resolveConfiguration(consumerRoot: File_System.File.Path) -> Lint.Configuration
    {
        return Lint.Driver.configuration(
            at: consumerRoot,
            manifestOverride: linter,
            onMissingLinterPath: {
                do throws(KernelWrite) {
                    _ = try Terminal.Stream.stderr.write(
                        Lint.CLI.bytes(
                            of: "[swift-linter] error: SWIFT_LINTER_PATH environment variable "
                                + "not set; cannot resolve manifest dependencies. Falling back "
                                + "to default (zero-rules) configuration.\n"
                        )
                    )
                } catch {

                }
            }
        )
    }

    func emit(_ findings: [Lint.Finding]) {

        format.emit(findings: findings, to: Terminal.Stream.stdout.write)
    }
}
