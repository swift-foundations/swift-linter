public import JSON
public import Linter_Primitives
public import Linter_Reporter_Text
public import Terminal_Primitives

#if !os(Windows)
  public import ISO_9945_Kernel_Terminal
#else
  public import Windows_32_Kernel_Terminal
#endif

extension Lint.Reporter {

  public enum SARIF {}
}

extension Lint.Reporter.SARIF {

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

extension Lint.Reporter.SARIF {

  public static func emit(
    findings: [Lint.Finding],
    to write: Terminal.Stream.Write
  ) {
    Self.write(bytes(of: report(for: findings) + "\n"), to: write)
  }

  public static func report(for findings: [Lint.Finding]) -> Swift.String {
    let document = sarifLog(for: findings)
    return document.serialize(pretty: true)
  }

  fileprivate static func sarifLog(for findings: [Lint.Finding]) -> JSON {
    [
      "version": "2.1.0",
      "$schema":
        "https://docs.oasis-open.org/sarif/sarif/v2.1.0/cs01/schemas/sarif-schema-2.1.0.json",
      "runs": [
        [
          "tool": [
            "driver": [
              "name": "swift-linter",
              "informationUri": "https://swift-institute.org",
              "rules": [],
            ]
          ],
          "results": JSON.array(findings.map(result(for:))),
        ]
      ],
    ]
  }

  static func result(for finding: Lint.Finding) -> JSON {
    let record = finding.record
    let pathOrID = record.location.filePath ?? record.location.fileID
    var fields: [(Swift.String, JSON)] = [
      ("ruleId", JSON(stringLiteral: record.identifier)),
      ("level", JSON(stringLiteral: level(for: record.severity))),
      ("message", ["text": JSON(stringLiteral: record.message)] as JSON),
      (
        "locations",
        [
          [
            "physicalLocation": [
              "artifactLocation": ["uri": JSON(stringLiteral: pathOrID)],
              "region": [
                "startLine": JSON(
                  integerLiteral: Int(record.location.line.underlying)
                ),
                "startColumn": JSON(
                  integerLiteral: Int(bitPattern: record.location.column)
                ),
              ],
            ]
          ]
        ] as JSON
      ),
    ]
    if let visibility = finding.visibility {

      let token: Swift.String = visibility.rawValue
      fields.append(
        (
          "properties",
          ["visibility": JSON(stringLiteral: token)] as JSON
        )
      )
    }
    return JSON.object(fields)
  }

  static func level(for severity: Diagnostic.Severity) -> Swift.String {
    switch severity {
    case .remark: "note"
    default: severity.wire.token
    }
  }
}

extension Lint.Reporter.SARIF {
  #if !os(Windows)
    fileprivate static func write(
      _ bytes: [Byte],
      to write: Terminal.Stream.Write
    ) {
      do throws(ISO_9945.Kernel.IO.Write.Error) { _ = try write(bytes) } catch {}
    }
  #else
    fileprivate static func write(
      _ bytes: [Swift.UInt8],
      to write: Terminal.Stream.Write
    ) {
      do throws(Windows.`32`.Kernel.IO.Write.Error) { _ = try write(bytes) } catch {}
    }
  #endif
}
