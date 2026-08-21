import File_System
import Linter_Primitives
import Testing

@testable import Linter_Core

extension Lint.Driver {
    @Suite
    struct Test {
        @Suite struct `Configuration From Manifest` {}
    }
}

extension Lint.Driver.Test.`Configuration From Manifest` {
    @Test
    func `Empty manifest with nil parent produces empty effective rules`() {
        let manifest = Lint.Manifest()
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        #expect(configuration.rules.effective.entries.isEmpty)
    }

    @Test
    func `Manifest enabledRuleIDs are silently ignored at engine layer`() {

        let manifest = Lint.Manifest(enabled: ["unchecked_call_site"])
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        #expect(configuration.rules.effective.entries.isEmpty)
    }

    @Test
    func `Manifest disabledRuleIDs are silently ignored at engine layer`() {

        let manifest = Lint.Manifest(
            disabled: ["unchecked_call_site"]
        )
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        #expect(configuration.rules.effective.entries.isEmpty)
    }

    @Test
    func `Child Configuration inherits from parent reference`() {

        let parentManifest = Lint.Manifest(enabled: ["unchecked_call_site"])
        let parentConfiguration = Lint.Driver.configuration(
            from: parentManifest,
            parent: nil
        )
        let childManifest = Lint.Manifest()
        let childConfiguration = Lint.Driver.configuration(
            from: childManifest,
            parent: parentConfiguration
        )
        #expect(childConfiguration.rules.effective.entries.isEmpty)
    }

    @Test
    func `Excluded paths are carried through to Configuration`() throws(Paths.Path.Error) {
        let manifest = Lint.Manifest(
            excluded: [
                try File.Path("Tests/Fixtures"),
                try File.Path(".build"),
            ]
        )
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        #expect(configuration.excluded == ["Tests/Fixtures", ".build"])
    }

    @Test
    func `Unknown rule ID is silently ignored`() {

        let manifest = Lint.Manifest(enabled: ["nonexistent_rule"])
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        #expect(configuration.rules.effective.entries.isEmpty)
    }
}
