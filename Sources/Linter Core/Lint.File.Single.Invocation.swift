internal import SwiftSyntax

extension Lint.File.Single {

    internal enum Invocation {}
}

extension Lint.File.Single.Invocation {

    internal static func find(in sourceFile: SourceFileSyntax) -> FunctionCallExprSyntax? {
        for item in sourceFile.statements {
            guard let expr: ExprSyntax = item.item.as(ExprSyntax.self) else { continue }
            guard let call: FunctionCallExprSyntax = expr.as(FunctionCallExprSyntax.self) else {
                continue
            }
            if isLintRunCall(call) {
                return call
            }
        }
        return nil
    }

    internal static func isLintRunCall(_ call: FunctionCallExprSyntax) -> Swift.Bool {
        if let member: MemberAccessExprSyntax = call.calledExpression.as(
            MemberAccessExprSyntax.self
        ) {
            guard member.declName.baseName.text == "run" else { return false }
            guard let base: DeclReferenceExprSyntax = member.base?.as(DeclReferenceExprSyntax.self)
            else {
                return true
            }
            return base.baseName.text == "Lint"
        }
        if let ref: DeclReferenceExprSyntax = call.calledExpression.as(DeclReferenceExprSyntax.self)
        {
            return ref.baseName.text == "run"
        }
        return false
    }
}
