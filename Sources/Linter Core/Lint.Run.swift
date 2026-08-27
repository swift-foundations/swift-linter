public import File_System
internal import Linter
import SwiftParser
import SwiftSyntax

extension Lint {

  public enum Run {}
}

extension Lint.Run {

  public static func run(
    paths: [File.Path],
    configuration: Lint.Configuration
  ) throws(Error) -> [Lint.Finding] {
    let outcome = try run(paths: paths, capturing: .all, configuration: configuration)
    return outcome.findings
  }

  public static func run(
    paths: [File.Path],
    capturing capture: Capture,
    configuration: Lint.Configuration
  ) throws(Error) -> Outcome {

    let effective = configuration.rules.effective.entries
    var manager = Source.Manager()
    var findings: [Lint.Finding] = []
    var suppressed: [Lint.Finding] = []
    var files: [File.Path] = []
    var observations: [Observation] = []
    var repairs: [Repair.Proposal] = []
    let controls = try Self.controls(for: effective)

    let types = Self.types(under: paths)
    for root in paths {
      let sourcePaths = Lint.Source.Walker.paths(under: root)
      for sourcePath in sourcePaths {
        let parsed = try parsedSource(
          root: root,
          relativePath: sourcePath,
          manager: &manager,
          types: types
        )
        let filePath = try Self.resolve(root: root, relativePath: sourcePath)
        files.append(filePath)
        let suppression = Lint.Suppression.scan(
          tree: parsed.tree,
          converter: parsed.converter
        )
        for entry in effective {
          let severity = entry.severity ?? entry.rule.severity.default
          let observation = entry.rule.observe(parsed, severity)
          observations.append(
            Observation(
              file: filePath,
              rule: entry.rule.id,
              coverage: observation.coverage,
              applicability: observation.applicability
            )
          )
          if !observation.findings.isEmpty {
            repairs.append(
              Repair.Proposal(
                file: filePath,
                rule: entry.rule.id,
                proposal: entry.rule.repair(parsed)
              )
            )
          }
          let candidates = observation.findings
          for record in candidates {
            let ruleID = Lint.Rule.ID(_unchecked: record.identifier)

            let visibility = parsed.visibility(at: record.location)
            let finding = Lint.Finding(
              record: record,
              visibility: visibility
            )
            if suppression.suppresses(line: record.location.line, rule: ruleID) {
              if capture != .findings {
                suppressed.append(finding)
              }
              continue
            }
            if capture != .suppressed {
              findings.append(finding)
            }
          }
        }
      }
    }
    return Outcome(
      findings: findings,
      suppressed: suppressed,
      files: files,
      rules: effective.map(\.rule.id),
      observations: observations,
      repairs: repairs,
      controls: controls
    )
  }

  fileprivate static func controls(
    for entries: [Lint.Rule.Configuration]
  ) throws(Error) -> [Control.Evidence] {
    var identities: Swift.Set<Lint.Rule.Control.ID> = []
    var evidence: [Control.Evidence] = []
    for entry in entries {
      guard !entry.rule.controls.isEmpty else {
        throw .invalidControlCatalog("rule '\(entry.rule.id.underlying)' has zero controls")
      }
      for control in entry.rule.controls {
        guard !control.id.underlying.isEmpty, identities.insert(control.id).inserted else {
          throw .invalidControlCatalog("duplicate or empty control identity")
        }
        switch control.expectation {
        case .clean:
          break
        case .findings(let count):
          guard count > 0 else {
            throw .invalidControlCatalog("control '\(control.id.underlying)' has invalid count")
          }
        }
        var manager = Source.Manager()
        let bytes = control.source.utf8.map(Byte.init)
        let path = control.path.underlying
        let fileID = manager.register(fileID: path, filePath: path, content: bytes)
        let file = manager.file(for: fileID)
        let tree = Parser.parse(source: control.source)
        let converter = SourceLocationConverter(fileName: path, tree: tree)
        let parsed = Lint.Source.Parsed(
          file: file,
          path: control.path,
          tree: tree,
          converter: converter,
          types: Lint.Brand.types(in: tree)
        )
        let severity = entry.severity ?? entry.rule.severity.default
        let observation = entry.rule.observe(parsed, severity)
        let coverage: Lint.Rule.Coverage
        if observation.applicability == control.applicability {
          coverage = observation.coverage
        } else {
          coverage = .unmeasured(
            .other(
              code: "control-applicability-mismatch",
              detail: control.id.underlying
            )
          )
        }
        evidence.append(
          .init(
            identity: control.id,
            rule: entry.rule.id,
            expectation: control.expectation,
            actualFindings: observation.findings.count,
            coverage: coverage
          )
        )
      }
    }
    return evidence
  }

  fileprivate static func resolve(
    root: File.Path,
    relativePath: Lint.Source.Path
  ) throws(Error) -> File.Path {
    guard !relativePath.underlying.isEmpty else { return root }
    do throws(Paths.Path.Error) {
      return root.appending(try File.Path(relativePath.underlying))
    } catch {
      throw .fileNotReadable(path: root)
    }
  }

  fileprivate static func parsedSource(
    root: File.Path,
    relativePath: Lint.Source.Path,
    manager: inout Source.Manager,
    types: Swift.Set<Swift.String>
  ) throws(Error) -> Lint.Source.Parsed {
    let absoluteString: Swift.String
    let filePath: File.Path
    if relativePath.underlying.isEmpty {
      absoluteString = root.description
      filePath = root
    } else {

      let relative: File.Path
      do throws(Paths.Path.Error) {
        relative = try File.Path(relativePath.underlying)
      } catch {

        throw .fileNotReadable(path: root)
      }
      filePath = root.appending(relative)
      absoluteString = filePath.description
    }
    let file = File(filePath)
    let bytes: [Byte]
    do throws(Either<File.System.Read.Full.Error, Never>) {
      bytes = try file.read.full { (span: Swift.Span<Byte>) in
        var copy: [Byte] = []
        copy.reserveCapacity(span.count)
        for index in span.indices { copy.append(span[index]) }
        return copy
      }
    } catch {
      throw .fileNotReadable(path: filePath)
    }
    guard let text = Swift.String(validating: bytes, as: UTF8.self) else {
      throw .nonUTF8(path: filePath)
    }
    let id = manager.register(fileID: absoluteString, filePath: absoluteString, content: bytes)
    let sourceFile = manager.file(for: id)
    let tree = Parser.parse(source: text)
    let converter = SourceLocationConverter(fileName: absoluteString, tree: tree)
    return Lint.Source.Parsed(
      file: sourceFile,
      path: relativePath,
      tree: tree,
      converter: converter,
      types: types
    )
  }

  fileprivate static func types(
    under paths: [File.Path]
  ) -> Swift.Set<Swift.String> {
    var names: Swift.Set<Swift.String> = []
    for root in paths {
      for sourcePath in Lint.Source.Walker.paths(under: root) {
        let filePath: File.Path
        if sourcePath.underlying.isEmpty {
          filePath = root
        } else {
          let relative: File.Path
          do throws(File.Path.Error) {
            relative = try File.Path(sourcePath.underlying)
          } catch {
            continue
          }
          filePath = root.appending(relative)
        }
        let file = File(filePath)
        let bytes: [Byte]
        do throws(Either<File.System.Read.Full.Error, Never>) {
          bytes = try file.read.full { (span: Swift.Span<Byte>) in
            var copy: [Byte] = []
            copy.reserveCapacity(span.count)
            for index in span.indices { copy.append(span[index]) }
            return copy
          }
        } catch {
          continue
        }
        guard let text = Swift.String(validating: bytes, as: UTF8.self) else { continue }
        let tree = Parser.parse(source: text)
        names.formUnion(Lint.Brand.types(in: tree))
      }
    }
    return names
  }
}
