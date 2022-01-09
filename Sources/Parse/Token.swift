import Basic

/// A token
public struct Token {

  /// The kind of the token.
  public var kind: Kind

  /// The range of the token in the source input.
  public var range: SourceRange

  public init(kind: Kind, range: SourceRange) {
    self.kind = kind
    self.range = range
  }

  /// The value of the token.
  ///
  /// - Parameter source: The source input from which the token was extracted.
  public func value(in source: String) -> Substring {
    return source[range]
  }

  /// The kind of a token.
  public enum Kind {

    case error

    case name
    case `struct`
    case `let`
    case `var`
    case fun
    case `if`
    case `in`
    case `while`
    case `inout`
    case `as`
    case int
    case float
    case comma
    case dot
    case colon
    case semi
    case query
    case bang
    case under
    case assign
    case amp
    case arrow
    case eq
    case ne
    case lt
    case le
    case gt
    case ge
    case add
    case sub
    case mul
    case div
    case lParen
    case rParen
    case lBrace
    case rBrace
    case lBracket
    case rBracket

  }

}
