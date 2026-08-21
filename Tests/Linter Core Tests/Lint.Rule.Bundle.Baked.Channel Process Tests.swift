import Environment
import Linter
import Process
import Testing

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

#if canImport(Darwin) || canImport(Glibc)

    extension Lint.Rule.Bundle.Baked.Channel.Test {
        @Suite struct Process {}
    }

    extension Lint.Rule.Bundle.Baked.Channel.Test.Process {
        fileprivate enum Executable {}
    }

    extension Lint.Rule.Bundle.Baked.Channel.Test.Process.Executable {
        fileprivate static let populated = "swift-linter-bundle-fixture"
        fileprivate static let empty = "swift-linter-bundle-empty-fixture"

        fileprivate static let singleBundle = "swift-linter-report-fixture"

        #if canImport(Darwin)
            fileprivate static let imageMarker: @convention(c) () -> Void = {}
        #endif

        fileprivate static func string(fromNulTerminated buffer: [CChar]) -> Swift.String {
            buffer.withUnsafeBufferPointer { pointer in
                guard let baseAddress = pointer.baseAddress else { return "" }
                return unsafe Swift.String(cString: baseAddress)
            }
        }

        fileprivate static func runningImagePath() -> Swift.String? {
            #if canImport(Darwin)
                var info = unsafe Dl_info()
                let address: UnsafeRawPointer = unsafe unsafeBitCast(
                    Self.imageMarker,
                    to: UnsafeRawPointer.self
                )
                guard unsafe dladdr(address, &info) != 0 else { return nil }
                guard let name = unsafe info.dli_fname else { return nil }
                return unsafe Swift.String(cString: name)
            #elseif canImport(Glibc)
                var buffer = [CChar](repeating: 0, count: 4096)
                let written = unsafe readlink("/proc/self/exe", &buffer, buffer.count - 1)
                guard written > 0 else { return nil }
                buffer[written] = 0
                return Self.string(fromNulTerminated: buffer)
            #else
                return nil
            #endif
        }

        fileprivate static func isExecutable(_ path: Swift.String) -> Swift.Bool {
            path.withCString { unsafe access($0, X_OK) == 0 }
        }

        fileprivate static func product(
            _ name: Swift.String,
            variable: Swift.String
        ) -> Swift.String? {
            if let value = unsafe getenv(variable) {
                let candidate = unsafe Swift.String(cString: value)
                if isExecutable(candidate) { return candidate }
            }
            guard let executable = runningImagePath(),
                let separator = executable.lastIndex(of: "/")
            else { return nil }
            var directory = Swift.String(executable[..<separator])
            for _ in 0..<5 {
                let candidate = "\(directory)/\(name)"
                if isExecutable(candidate) { return candidate }
                guard let separator = directory.lastIndex(of: "/"),
                    separator != directory.startIndex
                else { break }
                directory = Swift.String(directory[..<separator])
            }
            return nil
        }

        fileprivate static func root(testFile: Swift.String = #filePath) -> Swift.String {
            var components =
                testFile
                .split(separator: "/", omittingEmptySubsequences: false)
                .map(Swift.String.init)
            _ = components.popLast()
            _ = components.popLast()
            _ = components.popLast()
            return components.joined(separator: "/")
        }

        fileprivate static func fixture(_ name: Swift.String) -> Swift.String {
            "\(root())/Tests/Fixtures/\(name)"
        }

        fileprivate static func environment(
            bundle: Swift.String?
        ) -> [Swift.String: Swift.String] {
            var values = Environment.Snapshot.current().values
            _ = values.removeValue(forKey: Lint.Rule.Bundle.Baked.Channel.variable)
            if let bundle { values[Lint.Rule.Bundle.Baked.Channel.variable] = bundle }
            return values
        }

        fileprivate static func run(
            _ executable: Swift.String,
            arguments: [Swift.String],
            environment: [Swift.String: Swift.String]
        ) -> Process.Output? {
            let configuration = Process.Spawn.Configuration(
                executable: executable,
                arguments: arguments,
                environment: environment,
                stdout: .pipe,
                stderr: .pipe,
                timeout: .seconds(600)
            )
            do throws(Process.Error) {
                return try Process.Spawn.run(configuration)
            } catch {
                Issue.record("spawn failed for \(executable): \(error)")
                return nil
            }
        }

        fileprivate static func stdout(_ output: Process.Output) -> Swift.String {
            Swift.String(decoding: output.stdout ?? [], as: UTF8.self)
        }

        fileprivate static func stderr(_ output: Process.Output) -> Swift.String {
            Swift.String(decoding: output.stderr ?? [], as: UTF8.self)
        }

        fileprivate static func missing(_ name: Swift.String) -> Swift.String {
            "helper executable '\(name)' not found from \(runningImagePath() ?? "<unknown image>")"
        }
    }

    extension Lint.Rule.Bundle.Baked.Channel.Test.Process {
        @Test
        func `Unset channel exits nonzero and names the missing channel`() {
            guard
                let runner = Executable.product(
                    Executable.populated,
                    variable: "SWIFT_LINTER_TEST_BUNDLE_FIXTURE"
                )
            else {
                Issue.record(Comment(rawValue: Executable.missing(Executable.populated)))
                return
            }
            guard
                let output = Executable.run(
                    runner,
                    arguments: [Executable.fixture("report-format-direct")],
                    environment: Executable.environment(bundle: nil)
                )
            else { return }
            #expect(output.status != .exited(code: 0))
            let stderr = Executable.stderr(output)
            #expect(stderr.contains("bundle channel"))
            #expect(stderr.contains(Lint.Rule.Bundle.Baked.Channel.variable))
            #expect(stderr.contains("unset"))
        }

        @Test
        func `Misspelled token exits nonzero`() {
            guard
                let runner = Executable.product(
                    Executable.populated,
                    variable: "SWIFT_LINTER_TEST_BUNDLE_FIXTURE"
                )
            else {
                Issue.record(Comment(rawValue: Executable.missing(Executable.populated)))
                return
            }
            guard
                let output = Executable.run(
                    runner,
                    arguments: [Executable.fixture("report-format-direct")],
                    environment: Executable.environment(bundle: "primitves")
                )
            else { return }
            #expect(output.status != .exited(code: 0))
            #expect(Executable.stderr(output).contains("bundle channel"))
        }

        @Test
        func `A valid token absent from this runner's catalogue exits nonzero and names the token`()
        {
            guard
                let runner = Executable.product(
                    Executable.singleBundle,
                    variable: "SWIFT_LINTER_TEST_RUNNER"
                )
            else {
                Issue.record(Comment(rawValue: Executable.missing(Executable.singleBundle)))
                return
            }

            guard
                let output = Executable.run(
                    runner,
                    arguments: [Executable.fixture("report-format-direct")],
                    environment: Executable.environment(bundle: "standards")
                )
            else { return }
            #expect(output.status != .exited(code: 0))
            let stderr = Executable.stderr(output)
            #expect(stderr.contains("bundle channel"))
            #expect(stderr.contains("standards"))
        }

        @Test
        func `primitives selects exactly the primitives bundle`() {
            assertSelectsExactlyOwnBundle(
                token: "primitives",
                identifier: "bundle fixture primitives"
            )
        }

        @Test
        func `standards selects exactly the standards bundle`() {
            assertSelectsExactlyOwnBundle(
                token: "standards",
                identifier: "bundle fixture standards"
            )
        }

        @Test
        func `institute selects exactly the institute bundle`() {
            assertSelectsExactlyOwnBundle(
                token: "institute",
                identifier: "bundle fixture institute"
            )
        }

        private func assertSelectsExactlyOwnBundle(
            token: Swift.String,
            identifier: Swift.String
        ) {
            guard
                let runner = Executable.product(
                    Executable.populated,
                    variable: "SWIFT_LINTER_TEST_BUNDLE_FIXTURE"
                )
            else {
                Issue.record(Comment(rawValue: Executable.missing(Executable.populated)))
                return
            }
            guard
                let output = Executable.run(
                    runner,
                    arguments: [Executable.fixture("report-format-direct")],
                    environment: Executable.environment(bundle: token)
                )
            else { return }
            let stdout = Executable.stdout(output)
            let stderr = Executable.stderr(output)

            #expect(stdout.contains(identifier))
            for other in ["primitives", "standards", "institute"] where other != token {
                #expect(!stdout.contains("bundle fixture \(other)"))
            }

            #expect(stderr.contains("1 active rule"))
            #expect(stderr.contains("1 file linted"))
            #expect(stderr.contains("1 violation"))
        }
    }

    extension Lint.Rule.Bundle.Baked.Channel.Test.Process {
        @Test
        func `A valid token whose baked set is empty is a hard error, not a clean run`() {
            guard
                let runner = Executable.product(
                    Executable.empty,
                    variable: "SWIFT_LINTER_TEST_BUNDLE_EMPTY_FIXTURE"
                )
            else {
                Issue.record(Comment(rawValue: Executable.missing(Executable.empty)))
                return
            }
            guard
                let output = Executable.run(
                    runner,
                    arguments: [Executable.fixture("report-format-direct")],
                    environment: Executable.environment(bundle: "primitives")
                )
            else { return }

            #expect(output.status != .exited(code: 0))
            #expect(Executable.stderr(output).contains("bundle channel"))
            #expect(Executable.stderr(output).contains("zero rules"))
        }
    }

#endif
