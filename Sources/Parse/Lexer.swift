/// A lexer that generates tokens out of an input source.
struct Lexer: IteratorProtocol {

  /// The source input of the lexer.
  var source: String

  /// The current index of the lexer in the source input.
  var index: String.Index

  /// Creates a new lexer.
  ///
  /// - Parameter source: The source input.
  init(source: String) {
    self.source = source
    self.index = source.startIndex
  }

  /// Generates the next token from the source.
  mutating func next() -> Token? {
    while index < source.endIndex {
      // Ignore whitespaces and comments.
      take(while: { $0.isWhitespace })
      if source.suffix(from: index).starts(with: "//") {
        take(while: { !$0.isNewline })
        continue
      }

      // We're ready to consume the next token!
      break
    }

    // Make sure we've not depleted the input stream.
    guard let head = peek() else { return nil }

    var token = Token(kind: .error, range: index ..< index)

    // Scan identifiers and keywords.
    if head.isLetter || (head == "_") {
      let word = take(while: { $0.isLetter || $0.isNumber || ($0 == "_") })
      token.range = token.range.lowerBound ..< index

      switch word {
      case "_"      : token.kind = .under
      case "as"     : token.kind = .as
      case "if"     : token.kind = .if
      case "in"     : token.kind = .in
      case "let"    : token.kind = .let
      case "var"    : token.kind = .var
      case "fun"    : token.kind = .fun
      case "inout"  : token.kind = .inout
      case "while"  : token.kind = .while
      case "struct" : token.kind = .struct
      default       : token.kind = .name
      }

      return token
    }

    // Scan for numbers.
    if head.isDigit {
      scanNumberLiteral(&token)
      return token
    }

    // Scan for operators and punctuation.
    switch head {
    case ",": token.kind = .comma
    case ".": token.kind = .dot
    case ":": token.kind = .colon
    case ";": token.kind = .semi
    case "?": token.kind = .query
    case "&": token.kind = .amp
    case "(": token.kind = .lParen
    case ")": token.kind = .rParen
    case "{": token.kind = .lBrace
    case "}": token.kind = .rBrace
    case "[": token.kind = .lBracket
    case "]": token.kind = .rBracket
    case "+": token.kind = .add
    case "*": token.kind = .mul
    case "/": token.kind = .div

    case "-":
      if source.suffix(from: index).starts(with: "->") {
        token.kind = .arrow
        index = source.index(after: index)
      } else {
        index = source.index(after: index)
        if peek()?.isDigit ?? false {
          scanNumberLiteral(&token)
        } else {
          token.kind = .sub
        }
        index = source.index(before: index)
      }

    case "=":
      if source.suffix(from: index).starts(with: "==") {
        token.kind = .eq
        index = source.index(after: index)
      } else {
        token.kind = .assign
      }

    case "!":
      if source.suffix(from: index).starts(with: "!=") {
        token.kind = .ne
        index = source.index(after: index)
      } else {
        token.kind = .bang
      }

    case "<":
      if source.suffix(from: index).starts(with: "<=") {
        token.kind = .le
        index = source.index(after: index)
      } else {
        token.kind = .lt
      }

    case ">":
      if source.suffix(from: index).starts(with: ">=") {
        token.kind = .ge
        index = source.index(after: index)
      } else {
        token.kind = .gt
      }

    default: break
    }

    index = source.index(after: index)
    token.range = token.range.lowerBound ..< index
    return token
  }

  private mutating func scanNumberLiteral(_ token: inout Token) {
    // Consume the integer part of the literal.
    take(while: { $0.isDigit })
    token.kind = .int

    // Consume the decimal part of the literal, if any.
    if peek() == "." {
      index = source.index(after: index)
      if take(while: { $0.isDigit }) != nil {
        token.kind = .float
      } else {
        index = source.index(before: index)
      }
    }

    // Consume an exponent, if any.
    if (peek() == "e") || (peek() == "E") {
      let i = index

      index = source.index(after: index)
      if (peek() == "+") || (peek() == "-") {
        index = source.index(after: index)
      }

      if take(while: { $0.isDigit }) != nil {
        token.kind = .float
      } else {
        index = i
      }
    }

    token.range = token.range.lowerBound ..< index
  }

  /// Returns the next character in the stream, without consuming it.
  private func peek() -> Character? {
    guard index < source.endIndex else { return nil }
    return source[index]
  }

  /// Consumes the longest sequence of characters that satisfy the given predicate.
  ///
  /// - Parameter predicate: A closure that accepts a character and returns whether it should be
  ///     included in the sequence.
  @discardableResult
  private mutating func take(while predicate: (Character) -> Bool) -> Substring? {
    let start = index
    while let ch = peek(), predicate(ch) {
      index = source.index(after: index)
    }

    return start < index
      ? source[start ..< index]
      : nil
  }

}

extension Character {

  /// A Boolean value indicating whether this character represents a decimal digit.
  var isDigit: Bool {
    return (48 ... 57) ~= (asciiValue ?? 0)
  }

}
