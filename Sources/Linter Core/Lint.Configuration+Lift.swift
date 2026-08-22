internal import Linter_Primitives

extension Lint.Configuration {

  public static func lift(
    manifest: Lint.Manifest,
    registry: [Lint.Rule.ID: Lint.Rule],
    inheriting parent: Lint.Configuration? = nil
  ) -> Lint.Configuration {
    var entries: [Lint.Rule.Configuration] = []
    for id in manifest.rules.enabled {
      if let rule: Lint.Rule = registry[id] {
        entries.append(Lint.Rule.Configuration.enable(rule))
      }
    }
    let exclusions: [Lint.Filter.Prefix] = manifest.excluded.map(Lint.Filter.Prefix.init)
    return Lint.Configuration(
      inheriting: parent,
      excluded: exclusions,
      disabled: manifest.rules.disabled
    ) {
      entries
    }
  }
}
