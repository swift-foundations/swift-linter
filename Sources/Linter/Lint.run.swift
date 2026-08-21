internal import File_System
public import Linter_Core
public import Linter_Primitives
internal import Process
public import SPM_Standard
internal import Standard_Library_Extensions
internal import Terminal_Primitives

extension Lint {

    public static func run(bundle: [Lint.Rule.Configuration]) {
        let base: Lint.Configuration = Self.Configuration { bundle }

        let selection: Lint.Manifest?
        do throws(Self.File.Single.Channel.Error) {
            selection = try Self.File.Single.Channel.selection.read()
        } catch {
            failLoud("selection-manifest channel: \(error)")
        }
        guard let selection else {
            run(configuration: base)
            return
        }
        var registry: [Lint.Rule.ID: Lint.Rule] = [:]
        for entry in bundle {
            registry[entry.rule.id] = entry.rule
        }
        let overlaid: Lint.Configuration = Self.Configuration.lift(
            manifest: selection,
            registry: registry,
            inheriting: base
        )
        run(configuration: overlaid)
    }

    public static func run(bundles: [Lint.Rule.Bundle.Baked: [Lint.Rule.Configuration]]) {
        let read: Lint.Rule.Bundle.Baked?
        do throws(Lint.Rule.Bundle.Baked.Channel.Error) {
            read = try Lint.Rule.Bundle.Baked.Channel.read()
        } catch {
            failLoud("bundle channel: \(error)")
        }
        guard let requested = read else {
            failLoud(
                "bundle channel (\(Lint.Rule.Bundle.Baked.Channel.variable)) is unset; "
                    + "the dispatcher must select a baked bundle before spawning this runner"
            )
        }
        guard let bundle: [Lint.Rule.Configuration] = bundles[requested] else {

            failLoud("bundle channel: this runner does not bake bundle '\(requested.rawValue)'")
        }
        guard !bundle.isEmpty else {

            failLoud(
                "bundle channel: bundle '\(requested.rawValue)' bakes zero rules; "
                    + "a zero-finding run from an empty rule set is not a clean result"
            )
        }
        run(bundle: bundle)
    }

    private static func failLoud(_ message: Swift.String) -> Never {
        Self.Reporter.Text.emit(error: message, to: Terminal.Stream.stderr.write)
        Process.exit(1)
    }

    public static func run(configuration: Lint.Configuration) {
        let arguments = Swift.CommandLine.arguments
        let pathStrings: [Swift.String] =
            arguments.count >= 2
            ? [Swift.String](arguments.dropFirst())
            : ["."]

        let consumerPaths: [File_System.File.Path]
        do throws(Paths.Path.Error) {
            consumerPaths = try pathStrings.map { (raw: Swift.String) throws(Paths.Path.Error) in
                try File_System.File.Path(raw)
            }
        } catch {
            print("[Lint] error: invalid path argument: \(error)")
            return
        }

        let format: Lint.Reporter.Format
        do throws(Lint.Reporter.Format.Channel.Error) {
            format = try Lint.Reporter.Format.Channel.read()
        } catch {
            failLoud("output-format channel: \(error)")
        }
        do throws(Self.Run.Error) {
            let outcome: Lint.Run.Outcome = try Self.Run.run(
                paths: consumerPaths,
                capturing: .all,
                configuration: configuration
            )
            switch format {
            case .structured:
                Self.Reporter.Text.emit(
                    text: Self.Reporter.Structured.report(for: outcome) + "\n",
                    to: Terminal.Stream.stdout.write
                )
            case .text, .sarif:
                format.emit(findings: outcome.findings, to: Terminal.Stream.stdout.write)
            }

            let package: Swift.String = consumerPaths.first?.components.last?.string ?? "."

            Self.Reporter.Text.emit(
                summaryFor: package,
                activeRules: configuration.rules.effective.entries.count,
                excludedRules: configuration.rules.effective.disabled.count,
                filesLinted: outcome.filesLinted,
                violations: outcome.violations.count,
                findings: outcome.findings.count,
                to: Terminal.Stream.stderr.write
            )

            let policy: Lint.Run.Policy?
            do throws(Lint.Run.Policy.Channel.Error) {
                policy = try Lint.Run.Policy.Channel.read()
            } catch {
                failLoud("exit-policy channel: \(error)")
            }
            if outcome.summary.unmeasuredObservations > 0 {
                Process.exit(2)
            }
            if policy?.fails(for: outcome.findings) == true {
                Process.exit(1)
            }
        } catch {
            print("[Lint] error: \(error)")
        }
    }

    public static func run(
        dependencies: [Package.Dependency],
        @Array<Lint.Rule.Configuration>.Builder rules: () -> [Lint.Rule.Configuration]
    ) {
        _ = dependencies
        let collected: [Lint.Rule.Configuration] = rules()
        var registry: [Lint.Rule.ID: Lint.Rule] = [:]
        for entry in collected {
            registry[entry.rule.id] = entry.rule
        }

        let parent: Lint.Configuration?
        do throws(Self.File.Single.Channel.Error) {
            parent = try Self.File.Single.configuration(parentOf: registry)
        } catch {
            failLoud("parent-manifest channel: \(error)")
        }
        let configuration = Self.Configuration(inheriting: parent) { collected }
        run(configuration: configuration)
    }
}
