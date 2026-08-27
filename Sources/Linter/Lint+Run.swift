internal import File_System
internal import JSON
public import Linter_Core
public import Linter
internal import Process
public import SPM_Standard
internal import Standard_Library_Extensions
internal import Terminal

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
    let arguments = [Swift.String](Swift.CommandLine.arguments.dropFirst())
    if arguments == ["--inventory"] {
      let inventories = bundles.keys.sorted { $0.token < $1.token }.map { bundle in
        JSON.object([
          ("bundle", JSON(stringLiteral: bundle.token)),
          (
            "rules",
            .array(
              (bundles[bundle] ?? []).map(\.rule.id.underlying).sorted().map(
                JSON.init(stringLiteral:)
              )
            )
          ),
        ])
      }
      let document = JSON.object([
        ("schema", 1),
        ("profileSchema", JSON(integerLiteral: Lint.Profile.schema)),
        ("structuredResultSchema", 2),
        ("bundles", .array(inventories)),
      ])
      Swift.print(document.serialize(pretty: false))
      return
    }
    if arguments.first == "--profile" {
      guard arguments.count >= 3 else {
        failLoud("profile invocation requires --profile <profile.json> <path> ...")
      }
      let profile: Lint.Profile
      do throws(Lint.Profile.Error) { profile = try .read(at: arguments[1]) } catch {
        failLoud("profile: \(error)")
      }
      guard let baked = bundles[profile.bundle] else {
        failLoud("profile: this runner does not bake bundle '\(profile.bundle.token)'")
      }
      let selected: [Lint.Rule.Configuration]
      do throws(Lint.Profile.Error) { selected = try profile.select(from: baked) } catch {
        failLoud("profile: \(error)")
      }
      run(
        configuration: Self.Configuration { selected },
        paths: [Swift.String](arguments.dropFirst(2))
      )
      return
    }
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

      failLoud("bundle channel: this runner does not bake bundle '\(requested.token)'")
    }
    guard !bundle.isEmpty else {

      failLoud(
        "bundle channel: bundle '\(requested.token)' bakes zero rules; "
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
    run(
      configuration: configuration,
      paths: [Swift.String](Swift.CommandLine.arguments.dropFirst())
    )
  }

  private static func run(
    configuration: Lint.Configuration,
    paths: [Swift.String]
  ) {
    let pathStrings = paths.isEmpty ? ["."] : paths

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
        activeRules: Cardinal(UInt(configuration.rules.effective.entries.count)),
        excludedRules: Cardinal(UInt(configuration.rules.effective.disabled.count)),
        filesLinted: Cardinal(UInt(outcome.files.count)),
        violations: Cardinal(UInt(outcome.violations.count)),
        findings: Cardinal(UInt(outcome.findings.count)),
        to: Terminal.Stream.stderr.write
      )

      let policy: Lint.Run.Policy?
      do throws(Lint.Run.Policy.Channel.Error) {
        policy = try Lint.Run.Policy.Channel.read()
      } catch {
        failLoud("exit-policy channel: \(error)")
      }
      if outcome.summary.unmeasured > 0 || !outcome.unmeasuredControls.isEmpty {
        Process.exit(2)
      }
      if !outcome.failedControls.isEmpty || policy?.fails(for: outcome.findings) == true {
        Process.exit(1)
      }
    } catch {
      failLoud("source measurement failed: \(error)")
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
