import AST
import Basic

extension Diagnostic {

  static func ambiguousOperatorReference(range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "ambiguous operator reference")
  }

  static func callToNonFuncType(_ type: Type, range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "call to non-function type '\(type)'")
  }

  static func duplicateParamDecl(decl: ParamDecl) -> Diagnostic {
    return Diagnostic(
      range: decl.range,
      message: "duplicate parameter declaration '\(decl.name)'")
  }

  static func duplicatePropDecl(decl: BindingDecl) -> Diagnostic {
    return Diagnostic(
      range: decl.range,
      message: "duplicate property declaration '\(decl.name)'")
  }

  static func duplicateStructDecl(decl: StructDecl) -> Diagnostic {
    return Diagnostic(
      range: decl.range,
      message: "duplicate struct declaration '\(decl.name)'")
  }

  static func emptyArrayLiteralWithoutContext(range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "empty array literal can't be typed without any context")
  }

  static func exclusiveAccessViolation(range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "possible violation of exclusive access")
  }

  static func immutableInout(type: Type, range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "cannot pass immutable value of type '\(type)' as inout argument")
  }

  static func immutableLValue(type: Type, range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "cannot assign to immutable variable of type '\(type)'")
  }

  static func indexingInNonArrayType(_ type: Type, range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "indexing in non-array type '\(type)'")
  }

  static func invalidArgCount(expected: Int, actual: Int, range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "invalid number of arguments: expected '\(expected)', for '\(actual)'")
  }

  static func invalidUseOfUnderscore(range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "keyword '_' can only be used on the left side of an assignment")
  }

  static func missingMember(member: String, in type: Type, range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "type '\(type)' has no member named '\(member)'")
  }

  static func typeError(expected: Type, actual: Type, range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "type error: expected '\(expected)', got '\(actual)'")
  }

  static func undefinedBinding(name: String, range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "undefined binding: '\(name)'")
  }

  static func undefinedOperator(
    kind: OperExpr.Kind, lhs: Type, rhs: Type, range: SourceRange
  ) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "undefined operator '\(kind)' for operands of type '\(lhs)' and \(rhs)")
  }

  static func undefinedOperator(expr: InfixExpr) -> Diagnostic {
    return undefinedOperator(
      kind: expr.oper.kind, lhs: expr.lhs.type!, rhs: expr.rhs.type!, range: expr.oper.range)
  }

  static func undefinedType(name: String, range: SourceRange) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "undefined type: '\(name)'")
  }

  static func invalidConversion(
    from lhs: Type, to rhs: Type, range: SourceRange
  ) -> Diagnostic {
    return Diagnostic(
      range: range,
      message: "conversion from type '\(lhs)' to type '\(rhs)' will always fail")
  }

}
