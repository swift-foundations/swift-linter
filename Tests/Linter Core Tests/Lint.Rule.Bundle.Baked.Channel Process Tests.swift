// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-linter open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-linter project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import Environment
import Linter
import Process
import Testing

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// MARK: - Lint.run(bundles:) end-to-end process controls
//
// `Lint.Rule.Bundle.Baked.Channel Tests.swift` covers the channel's own
// read/write contract in-process. These tests spawn the REAL prebuilt
// runner (`swift-linter-bundle-fixture`, baking three distinguishable
// rules — one per baked-bundle token — and `swift-linter-bundle-empty-
// fixture`, baking a valid token to zero rules) to prove `Lint.run(bundles:)`
// itself — the code this task's fallback removal actually changed — refuses
// every fail-open shape:
//
//   - an UNSET channel exits non-zero and NAMES the missing channel
//     (rather than silently defaulting to `.primitives`);
//   - a SET-but-invalid token exits non-zero;
//   - `primitives`, `standards`, and `institute` each select EXACTLY their
//     own bundle — never a different one, never all three;
//   - a valid token whose baked set is empty is a hard error, not a clean
//     zero-finding run (the exact §3 item 9 fail-open shape one layer
//     inside the channel read itself).

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
        // Bakes ONLY `.primitives` (see `Tests/Fixtures/report-format-executable`)
        // — reused here as the catalogue-miss fixture: a VALID token
        // (`standards`) this runner's `bundles:` dictionary never baked.
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
        func `A valid token absent from this runner's catalogue exits nonzero and names the token`() {
            guard
                let runner = Executable.product(
                    Executable.singleBundle,
                    variable: "SWIFT_LINTER_TEST_RUNNER"
                )
            else {
                Issue.record(Comment(rawValue: Executable.missing(Executable.singleBundle)))
                return
            }
            // `swift-linter-report-fixture` only bakes `.primitives`.
            // `standards` is a real, valid token — just not one this
            // particular runner's `bundles:` dictionary carries.
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
            assertSelectsExactlyOwnBundle(token: "primitives", identifier: "bundle fixture primitives")
        }

        @Test
        func `standards selects exactly the standards bundle`() {
            assertSelectsExactlyOwnBundle(token: "standards", identifier: "bundle fixture standards")
        }

        @Test
        func `institute selects exactly the institute bundle`() {
            assertSelectsExactlyOwnBundle(token: "institute", identifier: "bundle fixture institute")
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
            // Exactly this token's rule fired — not the other two bundles'
            // rules, and not zero rules either.
            #expect(stdout.contains(identifier))
            for other in ["primitives", "standards", "institute"] where other != token {
                #expect(!stdout.contains("bundle fixture \(other)"))
            }
            // The run summary proves a non-zero active-rule count AND a
            // non-zero files-linted count — the exact §3 item 9 evidence
            // requirement — rather than trusting a bare "0 findings"/"clean"
            // result that could equally be produced by an unset or
            // wrong-selected channel.
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
            // §3 item 9 / this task's fourth positive control: a linter run
            // that loaded zero active rules and therefore found zero
            // violations must NOT be able to report clean (exit 0). The
            // token was valid and present in the catalogue — only the
            // resolved rule set was empty — so this is the exact shape a
            // silently-defaulted or silently-substituted bundle could
            // produce, and it must be UNMEASURED/failure.
            #expect(output.status != .exited(code: 0))
            #expect(Executable.stderr(output).contains("bundle channel"))
            #expect(Executable.stderr(output).contains("zero rules"))
        }
    }

#endif
