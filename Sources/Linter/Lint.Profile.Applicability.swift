extension Lint.Profile {
  public struct Applicability: Hashable, Sendable {
    public let rule: Lint.Rule.ID
    public let excludedTargets: [Target]

    public init(
      rule: Lint.Rule.ID,
      excludedTargets: [Target]
    ) throws(Lint.Profile.Error) {
      guard !excludedTargets.isEmpty else {
        throw .malformed("rule applicability has zero excluded targets")
      }
      guard Set(excludedTargets).count == excludedTargets.count else {
        throw .malformed("duplicate applicability target")
      }
      self.rule = rule
      self.excludedTargets = excludedTargets.sorted { $0.underlying < $1.underlying }
    }
  }
}

extension Lint.Profile.Applicability {
  func apply(
    to configuration: Lint.Rule.Configuration
  ) -> Lint.Rule.Configuration {
    let original = configuration.rule
    let filter = Lint.Filter.excluding(excludedTargets.map(\.sourcePrefix))
    let filtered = original.filtered(toPaths: filter)
    let configured = Lint.Rule(
      id: original.id,
      default: original.severity.default,
      suppression: original.suppression,
      controls: original.controls + controls(for: original),
      observe: filtered.observe,
      repair: filtered.repair
    )
    return Lint.Rule.Configuration(
      rule: configured,
      mode: configuration.mode,
      severity: configuration.severity
    )
  }

  private func controls(for rule: Lint.Rule) -> [Lint.Rule.Control] {
    guard let firing = rule.controls.first(where: { $0.expectation.count > 0 }) else {
      return []
    }
    var controls: [Lint.Rule.Control] = []
    controls.reserveCapacity(excludedTargets.count * 4)
    for target in excludedTargets {
      let declared = target.underlying
      let ordinary = undeclaredTarget("Ordinary Target")
      let neighbor = undeclaredTarget("\(declared) Convenience")
      let identity = "profile applicability \(rule.id.underlying) \(declared)"
      controls.append(contentsOf: [
        .init(
          id: "\(identity) declared target terminology",
          source: firing.source,
          path: "Sources/\(declared)/Specification.swift",
          expectation: .clean,
          applicability: .inapplicable
        ),
        .init(
          id: "\(identity) undeclared ordinary target",
          source: firing.source,
          path: "Sources/\(ordinary)/Vocabulary.swift",
          expectation: firing.expectation
        ),
        .init(
          id: "\(identity) neighboring target",
          source: firing.source,
          path: "Sources/\(neighbor)/Vocabulary.swift",
          expectation: firing.expectation
        ),
        .init(
          id: "\(identity) matching file name outside target",
          source: firing.source,
          path: "Sources/\(ordinary)/\(declared).swift",
          expectation: firing.expectation
        ),
      ])
    }
    return controls
  }

  private func undeclaredTarget(_ proposed: Swift.String) -> Swift.String {
    let declared = Set(excludedTargets.map(\.underlying))
    var candidate = proposed
    while declared.contains(candidate) { candidate += "_" }
    return candidate
  }
}
