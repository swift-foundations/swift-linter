public import Linter_Core
public import Terminal_Primitives

#if !os(Windows)
    public import ISO_9945_Kernel_Terminal
#else
    public import Windows_32_Kernel_Terminal
#endif

extension Lint.Reporter {

    public enum Text {}
}

extension Lint.Reporter.Text {

    #if !os(Windows)
        fileprivate typealias Kernel = ISO_9945.Kernel.IO.Write.Error
    #else
        fileprivate typealias Kernel = Windows.`32`.Kernel.IO.Write.Error
    #endif
}

extension Lint.Reporter.Text {

    #if !os(Windows)
        fileprivate static func bytes(of text: Swift.String) -> [Byte] {
            text.utf8.map(Byte.init)
        }
    #else
        fileprivate static func bytes(of text: Swift.String) -> [Swift.UInt8] {
            Swift.Array(text.utf8)
        }
    #endif
}

extension Lint.Reporter.Text {

    public static func emit(
        findings: [Lint.Finding],
        to write: Terminal.Stream.Write
    ) {
        for finding in findings {
            do throws(Kernel) {
                _ = try write(bytes(of: line(for: finding) + "\n"))
            } catch {

            }
        }
    }

    public static func emit(
        summaryFor package: Swift.String,
        activeRules: Swift.Int,
        excludedRules: Swift.Int,
        filesLinted: Swift.Int,
        violations: Swift.Int,
        findings: Swift.Int,
        to write: Terminal.Stream.Write
    ) {
        let line: Swift.String = Summary.line(
            package: package,
            activeRules: activeRules,
            excludedRules: excludedRules,
            filesLinted: filesLinted,
            violations: violations,
            findings: findings
        )
        do throws(Kernel) {
            _ = try write(bytes(of: line + "\n"))
        } catch {

        }
    }

    public static func emit(
        text: Swift.String,
        to write: Terminal.Stream.Write
    ) {
        do throws(Kernel) {
            _ = try write(bytes(of: text))
        } catch {

        }
    }

    public static func emit(
        error message: Swift.String,
        to write: Terminal.Stream.Write
    ) {
        do throws(Kernel) {
            _ = try write(bytes(of: "[Lint] error: " + message + "\n"))
        } catch {

        }
    }

    public static func report(for findings: [Lint.Finding]) -> Swift.String {
        findings
            .map(line(for:))
            .joined(separator: "\n")
    }

    public static func line(for finding: Lint.Finding) -> Swift.String {
        let record = finding.record
        let location = record.location
        let pathOrID = location.filePath ?? location.fileID
        let prefix = "\(pathOrID):\(location.line):\(location.column): "
        let severity = "\(record.severity.wire.token): "
        let body = "\(record.identifier): \(record.message)"
        let line = prefix + severity + body
        guard let visibility = finding.visibility else { return line }

        let token: Swift.String = visibility.rawValue
        return line + " [visibility: \(token)]"
    }
}
