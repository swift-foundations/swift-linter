public import Linter
public import SwiftSyntax

extension Lint {

  public struct Suppression: Sendable, Equatable {

    public let entries: [Lint.Suppression.Entry]

    @inlinable
    public init(entries: [Lint.Suppression.Entry] = []) {
      self.entries = entries
    }
  }
}

extension Lint.Suppression {

  public static let empty: Self = Self()
}

extension Lint.Suppression {

  @inlinable
  public func suppresses(line: Text.Line.Number, rule: Lint.Rule.ID) -> Swift.Bool {
    for entry in entries where entry.line == line && entry.rule == rule {
      return true
    }
    return false
  }

  @inlinable
  public func entries(suppressing line: Text.Line.Number, rule: Lint.Rule.ID) -> [Entry] {
    entries.filter { $0.line == line && $0.rule == rule }
  }
}

extension Lint.Suppression {

  fileprivate static let disableNextPrefix: Swift.String = "// swift-linter:disable:next "

  fileprivate static let disableLinePrefix: Swift.String = "// swift-linter:disable:line "

  fileprivate static let reasonPrefix: Swift.String = "// REASON:"
}

extension Lint.Suppression {

  public static func scan(
    tree: SourceFileSyntax,
    converter: SourceLocationConverter
  ) -> Lint.Suppression {
    var entries: [Lint.Suppression.Entry] = []

    for token in tree.tokens(viewMode: .sourceAccurate) {
      scanTrivia(
        token.leadingTrivia,

        tokenStartPosition: token.position,
        converter: converter,
        tree: tree,
        entries: &entries
      )
      scanTrivia(
        token.trailingTrivia,
        tokenStartPosition: token.endPositionBeforeTrailingTrivia,
        converter: converter,
        tree: tree,
        entries: &entries
      )
    }

    return Lint.Suppression(entries: entries)
  }

  fileprivate static func scanTrivia(
    _ trivia: Trivia,
    tokenStartPosition: AbsolutePosition,
    converter: SourceLocationConverter,
    tree: SourceFileSyntax,
    entries: inout [Lint.Suppression.Entry]
  ) {
    var cursor = tokenStartPosition

    var pendingReasonIndex: Swift.Int? = nil

    for piece in trivia {
      let pieceStart = cursor
      let pieceLength = piece.sourceLength
      defer { cursor = cursor.advanced(by: pieceLength.utf8Length) }

      let text: Swift.String
      switch piece {
      case .lineComment(let comment):
        text = comment

      default:

        continue
      }

      let directiveLine = converter.location(for: pieceStart).line

      if text.hasPrefix(Self.disableNextPrefix) {
        let suffix = Swift.String(text.dropFirst(Self.disableNextPrefix.count))
        let ruleID = ruleIDFromDirectiveSuffix(suffix)
        let suppressedLine = nextCodeLine(
          afterDirectiveLine: directiveLine,
          tree: tree,
          converter: converter
        )
        if let suppressedLine {
          let newIndex = entries.count
          entries.append(
            Self.Entry(
              line: Text.Line.Number(UInt(suppressedLine)),
              rule: ruleID,
              reason: nil
            )
          )
          pendingReasonIndex = newIndex
        } else {
          pendingReasonIndex = nil
        }
      } else if text.hasPrefix(Self.disableLinePrefix) {
        let suffix = Swift.String(text.dropFirst(Self.disableLinePrefix.count))
        let ruleID = ruleIDFromDirectiveSuffix(suffix)

        let newIndex = entries.count
        entries.append(
          Self.Entry(
            line: Text.Line.Number(UInt(directiveLine)),
            rule: ruleID,
            reason: nil
          )
        )
        pendingReasonIndex = newIndex
      } else if text.hasPrefix(Self.reasonPrefix),
        let pending = pendingReasonIndex,
        pending < entries.count
      {

        let reasonBody = Swift.String(text.dropFirst(Self.reasonPrefix.count))
        let trimmed = reasonBody.trimmingPrefixWhitespace()
        let previous = entries[pending].reason
        let combined: Swift.String
        if let previous {
          combined = previous + " " + trimmed
        } else {
          combined = trimmed
        }
        entries[pending] = Self.Entry(
          line: entries[pending].line,
          rule: entries[pending].rule,
          reason: combined
        )
      } else {

        pendingReasonIndex = nil
      }
    }
  }

  fileprivate static func ruleIDFromDirectiveSuffix(_ suffix: Swift.String) -> Lint.Rule.ID {
    var trimmed = suffix
    while let last = trimmed.last, last.isWhitespace {
      trimmed.removeLast()
    }
    return Lint.Rule.ID(_unchecked: trimmed)
  }

  fileprivate static func nextCodeLine(
    afterDirectiveLine directiveLine: Swift.Int,
    tree: SourceFileSyntax,
    converter: SourceLocationConverter
  ) -> Swift.Int? {
    for token in tree.tokens(viewMode: .sourceAccurate) {
      let tokenLine = converter.location(for: token.positionAfterSkippingLeadingTrivia).line
      if tokenLine > directiveLine {
        return tokenLine
      }
    }
    return nil
  }
}

extension Swift.String {
  fileprivate func trimmingPrefixWhitespace() -> Swift.String {
    var copy = self
    while let first = copy.first, first.isWhitespace {
      copy.removeFirst()
    }
    return copy
  }
}
