internal import Linter_Primitives
internal import SwiftSyntax

extension Lint.Source.Parsed {

    internal borrowing func visibility(at location: Source.Location) -> Lint.Visibility {
        guard let position = absolutePosition(for: location) else {
            return .internal
        }
        guard let node = deepestNode(containing: position) else {
            return .internal
        }
        return Lint.Visibility.effective(of: node)
    }

    private borrowing func absolutePosition(for location: Source.Location) -> AbsolutePosition? {

        guard location.line >= 1, location.column >= 1 else { return nil }
        let lineStarts = converter.sourceLines
        guard location.line.underlying <= UInt(lineStarts.count) else { return nil }

        return converter.position(
            ofLine: Int(location.line.underlying),
            column: Int(bitPattern: location.column)
        )
    }

    private borrowing func deepestNode(containing position: AbsolutePosition) -> Syntax? {
        let root = Syntax(tree)
        guard root.positionAfterSkippingLeadingTrivia <= position,
            position < root.endPosition
        else {
            return nil
        }
        var best: Syntax = root
        var cursor: Syntax = root

        while true {
            var descended = false
            for child in cursor.children(viewMode: .sourceAccurate) {
                if child.positionAfterSkippingLeadingTrivia <= position,
                    position < child.endPosition
                {
                    cursor = child
                    best = child
                    descended = true
                    break
                }
            }
            if !descended { break }
        }
        return best
    }
}
