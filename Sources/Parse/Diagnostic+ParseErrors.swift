import AST
import Basic

extension Diagnostic {

  static func expectedPath(expr: Expr) -> Diagnostic {
    return Diagnostic(
      range: expr.range,
      message: "expected path, got expression")
  }

  static func invalidLiteral(value: Substring, range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "invalid literal value '\(value)'")
  }

}
