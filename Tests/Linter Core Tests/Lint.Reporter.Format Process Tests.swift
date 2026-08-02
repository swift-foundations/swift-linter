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
import JSON
import Linter
import Process
import Testing

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

#if canImport(Darwin) || canImport(Glibc)

    extension Lint.Reporter.Format.Test {
        fileprivate enum Executable {}
    }

    extension Lint.Reporter.Format.Test.Executable {
        fileprivate static let cli = "swift-linter"
        fileprivate static let runner = "swift-linter-report-fixture"

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

        fileprivate static func root(
            testFile: Swift.String = #filePath
        ) -> Swift.String {
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
            format: Swift.String? = nil,
            policy: Swift.String? = nil,
            runner: Swift.String? = nil,
            linter: Swift.String? = nil
        ) -> [Swift.String: Swift.String] {
            var values = Environment.Snapshot.current().values
            _ = values.removeValue(forKey: Lint.Reporter.Format.Channel.variable)
            _ = values.removeValue(forKey: Lint.Run.Policy.Channel.variable)
            _ = values.removeValue(forKey: Lint.Rule.Bundle.Baked.Channel.variable)
            _ = values.removeValue(forKey: Lint.File.Single.Channel.selection.variable)
            _ = values.removeValue(forKey: Lint.File.Single.Channel.parent.variable)
            _ = values.removeValue(forKey: "SWIFT_LINTER_RUNNER")
            _ = values.removeValue(forKey: "SWIFT_LINTER_PATH")
            if let format { values[Lint.Reporter.Format.Channel.variable] = format }
            if let policy { values[Lint.Run.Policy.Channel.variable] = policy }
            if let runner { values["SWIFT_LINTER_RUNNER"] = runner }
            if let linter { values["SWIFT_LINTER_PATH"] = linter }
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

        fileprivate static func expectSARIF(
            _ output: Process.Output,
            results expectedResults: Swift.Int,
            violations expectedViolations: Swift.Int
        ) {
            let stdout = Self.stdout(output)
            let stderr = Self.stderr(output)
            #expect(!stdout.isEmpty)
            #expect(!stdout.contains("active rules"))
            #expect(!stdout.contains("files linted"))
            #expect(!stdout.contains("violations"))
            #expect(stderr.contains("active rules"))
            #expect(stderr.contains("files linted"))
            #expect(stderr.contains("\(expectedViolations) violations"))

            let document: JSON
            do throws(JSON.Error) {
                document = try JSON.parse(stdout)
            } catch {
                Issue.record("stdout was not one valid JSON document: \(error)\n\(stdout)")
                return
            }
            let results = document.runs[0].results.array
            #expect(Swift.String(document.version) == "2.1.0")
            #expect(results?.count == expectedResults)
            if expectedResults == 1 {
                #expect(Swift.String(results?[0].ruleId) == "report format fixture")
                #expect(Swift.String(results?[0].level) == "error")
                #expect(Swift.String(results?[0].message.text) == "fixture rule fired")
            }
        }

        fileprivate static func missing(_ name: Swift.String) -> Swift.String {
            "helper executable '\(name)' not found from \(runningImagePath() ?? "<unknown image>")"
        }
    }

    extension Lint.Reporter.Format.Test.Integration {
        @Test
        func `Direct CLI emits one empty SARIF document and keeps its summary on stderr`() {
            guard
                let cli = Lint.Reporter.Format.Test.Executable.product(
                    Lint.Reporter.Format.Test.Executable.cli,
                    variable: "SWIFT_LINTER_TEST_CLI"
                )
            else {
                Issue.record(
                    Comment(
                        rawValue: Lint.Reporter.Format.Test.Executable.missing(
                            Lint.Reporter.Format.Test.Executable.cli
                        )
                    )
                )
                return
            }
            guard
                let output = Lint.Reporter.Format.Test.Executable.run(
                    cli,
                    arguments: [
                        "--format", "sarif",
                        "--exit-policy", "strict",
                        Lint.Reporter.Format.Test.Executable.fixture("report-format-direct"),
                    ],
                    environment: Lint.Reporter.Format.Test.Executable.environment()
                )
            else { return }
            #expect(output.status == .exited(code: 0))
            Lint.Reporter.Format.Test.Executable.expectSARIF(
                output,
                results: 0,
                violations: 0
            )
        }

        @Test
        func `Nested package preserves SARIF and strict exit through its spawned executable`() {
            guard
                let cli = Lint.Reporter.Format.Test.Executable.product(
                    Lint.Reporter.Format.Test.Executable.cli,
                    variable: "SWIFT_LINTER_TEST_CLI"
                )
            else {
                Issue.record(
                    Comment(
                        rawValue: Lint.Reporter.Format.Test.Executable.missing("swift-linter")
                    )
                )
                return
            }
            guard
                let output = Lint.Reporter.Format.Test.Executable.run(
                    cli,
                    arguments: [
                        "--format", "sarif",
                        "--exit-policy", "strict",
                        Lint.Reporter.Format.Test.Executable.fixture("report-format-nested"),
                    ],
                    environment: Lint.Reporter.Format.Test.Executable.environment()
                )
            else { return }
            #expect(output.status == .exited(code: 1))
            Lint.Reporter.Format.Test.Executable.expectSARIF(
                output,
                results: 1,
                violations: 1
            )
        }

        @Test
        func `Eval fallback preserves SARIF and strict exit through its generated executable`() {
            guard
                let cli = Lint.Reporter.Format.Test.Executable.product(
                    Lint.Reporter.Format.Test.Executable.cli,
                    variable: "SWIFT_LINTER_TEST_CLI"
                )
            else {
                Issue.record(
                    Comment(
                        rawValue: Lint.Reporter.Format.Test.Executable.missing("swift-linter")
                    )
                )
                return
            }
            guard
                let output = Lint.Reporter.Format.Test.Executable.run(
                    cli,
                    arguments: [
                        "--format", "sarif",
                        "--exit-policy", "strict",
                        Lint.Reporter.Format.Test.Executable.fixture("report-format-eval"),
                    ],
                    environment: Lint.Reporter.Format.Test.Executable.environment(
                        linter: Lint.Reporter.Format.Test.Executable.root()
                    )
                )
            else { return }
            #expect(output.status == .exited(code: 1))
            Lint.Reporter.Format.Test.Executable.expectSARIF(
                output,
                results: 1,
                violations: 1
            )
        }

        @Test
        func `Prebuilt runner preserves SARIF and strict exit through the provisioned binary`() {
            guard
                let cli = Lint.Reporter.Format.Test.Executable.product(
                    Lint.Reporter.Format.Test.Executable.cli,
                    variable: "SWIFT_LINTER_TEST_CLI"
                ),
                let runner = Lint.Reporter.Format.Test.Executable.product(
                    Lint.Reporter.Format.Test.Executable.runner,
                    variable: "SWIFT_LINTER_TEST_RUNNER"
                )
            else {
                Issue.record("swift-linter or swift-linter-report-fixture executable not found")
                return
            }
            guard
                let output = Lint.Reporter.Format.Test.Executable.run(
                    cli,
                    arguments: [
                        "--format", "sarif",
                        "--exit-policy", "strict",
                        Lint.Reporter.Format.Test.Executable.fixture("report-format-runner"),
                    ],
                    environment: Lint.Reporter.Format.Test.Executable.environment(runner: runner)
                )
            else { return }
            #expect(output.status == .exited(code: 1))
            Lint.Reporter.Format.Test.Executable.expectSARIF(
                output,
                results: 1,
                violations: 1
            )
        }

        @Test
        func `Unset format remains byte identical to explicit text in a configured executable`() {
            guard
                let runner = Lint.Reporter.Format.Test.Executable.product(
                    Lint.Reporter.Format.Test.Executable.runner,
                    variable: "SWIFT_LINTER_TEST_RUNNER"
                )
            else {
                Issue.record(
                    Comment(
                        rawValue: Lint.Reporter.Format.Test.Executable.missing(
                            "swift-linter-report-fixture"
                        )
                    )
                )
                return
            }
            let arguments = [Lint.Reporter.Format.Test.Executable.fixture("report-format-direct")]
            guard
                let unset = Lint.Reporter.Format.Test.Executable.run(
                    runner,
                    arguments: arguments,
                    environment: Lint.Reporter.Format.Test.Executable.environment()
                ),
                let text = Lint.Reporter.Format.Test.Executable.run(
                    runner,
                    arguments: arguments,
                    environment: Lint.Reporter.Format.Test.Executable.environment(
                        format: Lint.Reporter.Format.Channel.value(.text)
                    )
                )
            else { return }
            #expect(unset.status == .exited(code: 0))
            #expect(text.status == .exited(code: 0))
            #expect(unset.stdout == text.stdout)
            #expect(unset.stderr == text.stderr)
            #expect(
                Lint.Reporter.Format.Test.Executable.stdout(unset).contains(
                    ":1:1: error: report format fixture: fixture rule fired"
                )
            )
            #expect(
                Lint.Reporter.Format.Test.Executable.stderr(unset).contains("1 violations")
            )
        }

        @Test
        func `Invalid format exits nonzero with a visible stderr diagnostic and no stdout`() {
            guard
                let runner = Lint.Reporter.Format.Test.Executable.product(
                    Lint.Reporter.Format.Test.Executable.runner,
                    variable: "SWIFT_LINTER_TEST_RUNNER"
                )
            else {
                Issue.record(
                    Comment(
                        rawValue: Lint.Reporter.Format.Test.Executable.missing(
                            "swift-linter-report-fixture"
                        )
                    )
                )
                return
            }
            guard
                let output = Lint.Reporter.Format.Test.Executable.run(
                    runner,
                    arguments: [
                        Lint.Reporter.Format.Test.Executable.fixture("report-format-direct")
                    ],
                    environment: Lint.Reporter.Format.Test.Executable.environment(format: "checkstyle")
                )
            else { return }
            #expect(output.status == .exited(code: 1))
            #expect(output.stdout?.isEmpty == true)
            #expect(
                Lint.Reporter.Format.Test.Executable.stderr(output).contains(
                    "[Lint] error: output-format channel:"
                )
            )
        }
    }

#endif
