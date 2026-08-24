internal import File_System
internal import JSON
public import Linter_Core

extension Lint {
  public struct Profile: Sendable {
    public let revision: Swift.String
    public let bundle: Lint.Rule.Bundle.Baked
    public let rules: [Lint.Rule.ID]
    public let applicability: [Applicability]

    public init(
      revision: Swift.String,
      bundle: Lint.Rule.Bundle.Baked,
      rules: [Lint.Rule.ID],
      applicability: [Applicability] = []
    ) throws(Error) {
      guard !revision.isEmpty else { throw .malformed("empty revision") }
      guard !rules.isEmpty else { throw .rules("zero rules") }
      guard Set(rules).count == rules.count else { throw .rules("duplicate rules") }
      guard Set(applicability.map(\.rule)).count == applicability.count else {
        throw .malformed("duplicate rule applicability")
      }
      let ruleSet = Set(rules)
      guard applicability.allSatisfy({ ruleSet.contains($0.rule) }) else {
        throw .rules("applicability names a rule outside the profile")
      }
      self.revision = revision
      self.bundle = bundle
      self.rules = rules
      self.applicability = applicability.sorted {
        $0.rule.underlying < $1.rule.underlying
      }
    }
  }
}

extension Lint.Profile {
  public static let schema = 2
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
      let bundle = object["bundle"], let rules = object["rules"],
      let applicability = object["applicability"]
    else { throw .malformed("missing required field") }
    let decodedSchema: Swift.Int
    let decodedRevision: Swift.String
    let decodedBundle: Swift.String
    let decodedRules: [Swift.String]
    let decodedApplicability: [(
      rule: Swift.String,
      targets: [(identity: Swift.String, sourceRoot: Swift.String)]
    )]
    do throws(JSON.Error) {
      decodedSchema = try Swift.Int(json: schema)
      decodedRevision = try Swift.String(json: revision)
      decodedBundle = try Swift.String(json: bundle)
      decodedRules = try [Swift.String](json: rules)
      decodedApplicability = try [JSON](json: applicability).map {
        entry throws(JSON.Error) -> (
          rule: Swift.String,
          targets: [(identity: Swift.String, sourceRoot: Swift.String)]
        ) in
        guard let object = entry.dictionary,
          let rule = object["rule"], let excludedTargets = object["excludedTargets"]
        else {
          throw JSON.Error.typeMismatch(
            expected: "rule applicability object",
            got: "missing rule or excludedTargets"
          )
        }
        let decodedRule = try Swift.String(json: rule)
        let decodedTargets = try [JSON](json: excludedTargets).map {
          target throws(JSON.Error) -> (
            identity: Swift.String,
            sourceRoot: Swift.String
          ) in
          guard let object = target.dictionary,
            let identity = object["identity"], let sourceRoot = object["sourceRoot"]
          else {
            throw JSON.Error.typeMismatch(
              expected: "target identity object",
              got: "missing identity or sourceRoot"
            )
          }
          return (
            try Swift.String(json: identity),
            try Swift.String(json: sourceRoot)
          )
        }
        return (decodedRule, decodedTargets)
      }
    } catch { throw .malformed("\(error)") }
    guard decodedSchema == Self.schema else { throw .schema(decodedSchema) }
    guard let baked = Lint.Rule.Bundle.Baked(rawValue: decodedBundle) else {
      throw .bundle(decodedBundle)
    }
    var ruleIDs: [Lint.Rule.ID] = []
    ruleIDs.reserveCapacity(decodedRules.count)
    for rule in decodedRules { ruleIDs.append(Lint.Rule.ID(rule)) }
    var applications: [Applicability] = []
    applications.reserveCapacity(decodedApplicability.count)
    for decoded in decodedApplicability {
      var targets: [Target] = []
      targets.reserveCapacity(decoded.targets.count)
      for target in decoded.targets {
        targets.append(
          try Target(target.identity, sourceRoot: target.sourceRoot)
        )
      }
      applications.append(
        try Applicability(rule: .init(decoded.rule), excludedTargets: targets)
      )
    }
    return try Self(
      revision: decodedRevision,
      bundle: baked,
      rules: ruleIDs,
      applicability: applications
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
    guard available.count == rules.count, Set(available.keys) == Set(rules) else {
      throw .rules("profile does not equal the complete baked bundle inventory")
    }
    let applicability = Dictionary(uniqueKeysWithValues: applicability.map { ($0.rule, $0) })
    var selected: [Lint.Rule.Configuration] = []
    selected.reserveCapacity(rules.count)
    for rule in rules {
      guard let configuration = available[rule] else {
        throw .rules("unknown rule \(rule.underlying)")
      }
      selected.append(applicability[rule]?.apply(to: configuration) ?? configuration)
    }
    return selected
  }
}
