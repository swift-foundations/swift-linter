public import Linter_Core

extension Lint.Reporter.Text {

    public enum Summary {}
}

extension Lint.Reporter.Text.Summary {

    public static func line(
        package: Swift.String,
        activeRules: Swift.Int,
        excludedRules: Swift.Int,
        filesLinted: Swift.Int,
        violations: Swift.Int,
        findings: Swift.Int
    ) -> Swift.String {
        let ruleSet: Swift.String =
            excludedRules > 0
            ? "\(activeRules) active rules (−\(excludedRules) excluded)"
            : "\(activeRules) active rules"
        let fileWord: Swift.String = filesLinted == 1 ? "file" : "files"
        let violationWord: Swift.String = violations == 1 ? "violation" : "violations"
        let findingWord: Swift.String = findings == 1 ? "finding" : "findings"
        return "\(package) · \(ruleSet) · \(filesLinted) \(fileWord) linted · "
            + "\(violations) \(violationWord) · \(findings) \(findingWord)"
    }
}
