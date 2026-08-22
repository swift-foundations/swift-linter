public import File_System
public import JSON
public import Linter_Primitives

extension Lint {

  public struct Manifest: Sendable, Hashable {

    public let rules: Rules

    public let excluded: [File_System.File.Path]

    public init(
      enabled: Set<Lint.Rule.ID> = [],
      disabled: Set<Lint.Rule.ID> = [],
      excluded: [File_System.File.Path] = []
    ) {
      self.rules = Rules(enabled: enabled, disabled: disabled)
      self.excluded = excluded
    }
  }
}

extension Lint.Manifest: JSON.Serializable {

  public static func serialize(_ value: Self) -> JSON {
    [
      "enabled": .array(value.rules.enabled.map { .string($0.underlying) }),
      "disabled": .array(value.rules.disabled.map { .string($0.underlying) }),
      "excluded": .array(value.excluded.map { .string($0.description) }),
    ]
  }

  public static func deserialize(_ json: JSON) throws(JSON.Error) -> Self {

    let enabledIDs: [Lint.Rule.ID] = try [Swift.String](json: json["enabled"]).map {
      Lint.Rule.ID($0)
    }
    let disabledIDs: [Lint.Rule.ID] = try [Swift.String](json: json["disabled"]).map {
      Lint.Rule.ID($0)
    }
    let enabled = Set(enabledIDs)
    let disabled = Set(disabledIDs)
    let excludedRaw = try [Swift.String](json: json["excluded"])
    let excluded: [File.Path] = try excludedRaw.map {
      (string: Swift.String) throws(JSON.Error) -> File.Path in
      do throws(Paths.Path.Error) {
        return try File.Path(string)
      } catch {
        throw JSON.Error.typeMismatch(
          expected: "File.Path string",
          got: "invalid path: \(string)"
        )
      }
    }
    return Self(
      enabled: enabled,
      disabled: disabled,
      excluded: excluded
    )
  }
}
