import File_System
import Testing

@testable import Linter_Core

extension Lint.File.Single.Channel {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

extension Lint.File.Single.Channel.Test {
    private static func freshRoot(key: Swift.String) -> File.Path {

        try! File.Path.Temporary.deterministic(prefix: "lint-channel-root-", key: key, suffix: "")
    }

    private static func writeFixture(key: Swift.String, content: Swift.String) -> File.Path {

        let path = try! File.Path.Temporary.deterministic(
            prefix: "lint-channel-file-",
            key: key,
            suffix: ".json"
        )

        try! File(path).write.atomic(content)
        return path
    }

    @Test
    func `An UNSET channel variable reads as nil (no overlay)`() throws(Lint.File.Single.Channel
        .Error)
    {

        let channel = Lint.File.Single.Channel(
            variable: "SWIFT_LINTER_TEST_DEFINITELY_UNSET_8F3A2B",
            basename: "test-manifest"
        )
        let manifest = try channel.read()
        #expect(manifest == nil)
    }

    @Test
    func `A SET-but-missing manifest HARD-ERRORS, never silently widens`() {

        let channel = Lint.File.Single.Channel.selection
        do throws(Lint.File.Single.Channel.Error) {
            _ = try channel.resolve(raw: "/nonexistent/swift-linter-test/selection-manifest.json")
            Issue.record(
                "resolve(raw:) must throw for a set-but-missing manifest, not return a value"
            )
        } catch {
            switch error {
            case .unreadable:
                break

            default:
                Issue.record("expected .unreadable, got \(error)")
            }
        }
    }

    @Test
    func `A SET-but-malformed manifest HARD-ERRORS as unparseable`() {
        let path = Self.writeFixture(key: "malformed", content: "this is not valid json {{{")
        let channel = Lint.File.Single.Channel.parent
        do throws(Lint.File.Single.Channel.Error) {
            _ = try channel.resolve(raw: path.string)
            Issue.record("resolve(raw:) must throw for a malformed manifest")
        } catch {
            switch error {
            case .unparseable:
                break

            default:
                Issue.record("expected .unparseable, got \(error)")
            }
        }
    }

    @Test
    func `Write then resolve round-trips the manifest`() throws(Lint.File.Single.Channel.Error) {
        let root = Self.freshRoot(key: "roundtrip")
        let manifest = Lint.Manifest(disabled: ["raw value access", "int public parameter"])
        let written = try Lint.File.Single.Channel.selection.write(
            manifest,
            consumerPackageRoot: root,
            nonce: "abc123"
        )
        let read = try Lint.File.Single.Channel.selection.resolve(raw: written.string)
        #expect(read == manifest)
    }

    @Test
    func `The nonce makes the temp-file name unique per run`() throws(Paths.Path.Error) {
        let root = try File.Path("/tmp/swift-linter-nonce-test")
        let fixed = try Lint.File.Single.Channel.selection.path(
            consumerPackageRoot: root,
            nonce: ""
        )
        let unique = try Lint.File.Single.Channel.selection.path(
            consumerPackageRoot: root,
            nonce: "deadbeef"
        )
        #expect(fixed.string.hasSuffix("selection-manifest.json"))
        #expect(unique.string.hasSuffix("selection-manifest-deadbeef.json"))
        #expect(fixed != unique)
    }
}
