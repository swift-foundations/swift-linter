import Linter

extension Lint.Rule {
  fileprivate static let `report format invalid fixture` = Lint.Rule(
    id: "report format invalid fixture",
    default: .error,
    observe: Lint.Rule.measured { _, _ in [] }
  )
}

Lint.run(bundles: [
  .primitives: [.enable(.`report format invalid fixture`)]
])
