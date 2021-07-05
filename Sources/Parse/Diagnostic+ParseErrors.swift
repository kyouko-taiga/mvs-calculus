import AST
import Basic
import Diesel

extension Diagnostic {

  static func expectedPath(expr: Expr) -> Diagnostic {
    return Diagnostic(
      range: expr.range,
      message: "expected path, got expression")
  }

  static func expectedToken(expectedKind: Token.Kind, actual: Token) -> Diagnostic {
    return Diagnostic(
      range: actual.range,
      message: "expected '\(expectedKind)', found '\(actual.kind)'")
  }

  static func expectedToken(expectedKind: Token.Kind, range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "expected '\(expectedKind)'")
  }

  static func expectedOperator(range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "expected operator")
  }

  static func missingPropertyAnnotation(range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "missing type annotation in property declaration")
  }

  static func invalidLiteral(value: Substring, range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "invalid literal value '\(value)'")
  }

}

extension DiagnosticConsumer {

  /// Consumes and reports a parse error.
  ///
  /// - Parameter error: The error to consume.
  func consume(error: ParseError, at range: SourceRange) {
    if let diag = error.diagnostic as? Diagnostic {
      consume(diag)
    } else {
      let diag = Diagnostic(
        range: range,
        message: error.diagnostic.map(String.init(describing:)) ?? "parse error")
      consume(diag)
    }
  }

}
