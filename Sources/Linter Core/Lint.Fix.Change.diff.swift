internal import Paths

extension Lint.Fix.Change {

    public var diff: Swift.String {
        let before: [Swift.Substring] = original.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        let after: [Swift.Substring] = fixed.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )

        var prefix = 0
        while prefix < before.count, prefix < after.count, before[prefix] == after[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < (before.count - prefix),
            suffix < (after.count - prefix),
            before[before.count - 1 - suffix] == after[after.count - 1 - suffix]
        {
            suffix += 1
        }

        let removed = before[prefix..<(before.count - suffix)]
        let added = after[prefix..<(after.count - suffix)]

        var lines: [Swift.String] = []
        lines.append("--- \(path.description)")
        lines.append("+++ \(path.description)")
        lines.append(
            "@@ -\(prefix + 1),\(removed.count) +\(prefix + 1),\(added.count) @@"
                + (rules.isEmpty ? "" : " " + rules.map(\.description).joined(separator: ", "))
        )
        for line in removed { lines.append("-\(line)") }
        for line in added { lines.append("+\(line)") }
        return lines.joined(separator: "\n") + "\n"
    }
}
