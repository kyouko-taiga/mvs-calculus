import AST
import Diesel

/// A parser.
public struct MVSParser {

  lazy var program = (structDecl >> take(.in)).many
    .then(expr)
    .map(Program.init)

  lazy var structDecl = take(.struct)
    .then(take(.name))
    .then(take(.lBrace), combine: { lhs, _ in lhs })
    .then(bindingDecl.many)
    .then(take(.rBrace))
    .assemble({ (state, tree) -> StructDecl in
      let (((head, name), props), tail) = tree
      let decl = StructDecl(
        name: String(name.value(in: state.source)),
        props: props,
        range: head.range.lowerBound ..< tail.range.upperBound)

      state.knownStructs.insert(decl.name)

      return decl
    })

  lazy var bindingDecl = take(where: { ($0.kind == .let) || ($0.kind == .var) })
    .then(take(.name))
    .then(take(.colon) << sign)
    .assemble({ (state, tree) throws -> BindingDecl in
      let ((head, name), sign) = tree

      return BindingDecl(
        mutability: head.kind == .let ? .let : .var,
        name: String(name.value(in: state.source)),
        sign: sign,
        range: head.range.lowerBound ..< sign.range.upperBound)
    })

  lazy var paramDeclList = paramDecl
    .then((take(.comma) << paramDecl).many >> take(.comma).optional)
    .map({ (head, tail) in
      [head] + tail
    })

  lazy var paramDecl = take(.name)
    .then(take(.colon) << sign)
    .assemble({ (state, tree) -> ParamDecl in
      let (name, sign) = tree
      return ParamDecl(
        name: String(name.value(in: state.source)), sign: sign,
        range: name.range.lowerBound ..< sign.range.upperBound)
    })

  let expr = ForwardParser<Expr, ParserState>()

  lazy var postExpr = preExpr
    .then(suffix.many)
    .assemble({ (state, tree) -> Expr in
      var (expr, suffixes) = tree

      for suffix in suffixes {
        switch suffix {
        case .call(let args, let tail):
          let range = expr.range.lowerBound ..< tail.range.upperBound

          // Check whether the expression is a struct literal, or an arbitrary function call.
          if let path = expr as? NamePath, (state.knownStructs.contains(path.name)) {
            expr = StructExpr(name: path.name, args: args, range: range)
          } else {
            expr = CallExpr(callee: expr, args: args, range: range)
          }

        case .subs(let index, let tail):
          let range = expr.range.lowerBound ..< tail.range.upperBound
          expr = ElemPath(base: expr, index: index, range: range)

        case .prop(let name):
          let range = expr.range.lowerBound ..< name.range.upperBound
          expr = PropPath(base: expr, name: String(name.value(in: state.source)), range: range)

        case .assign(let rhs, let body):
          guard let lhs = expr as? Path else {
            throw ParseError(diagnostic: Diagnostic.expectedPath(expr: expr))
          }
          let range = lhs.range.lowerBound ..< body.range.upperBound
          expr = AssignExpr(lvalue: lhs, rvalue: rhs, body: body, range: range)
        }
      }

      return expr
    })

  lazy var suffix = callSuffix
    .or(subscriptSuffix)
    .or(propSuffix)
    .or(assignSuffix)

  lazy var callSuffix = ((take(.lParen) << exprList.optional) ++ take(.rParen))
    .map({ (args, tail) -> Suffix in
      .call(args: args ?? [], tail: tail)
    })

  lazy var subscriptSuffix = ((take(.lBracket) << expr) ++ take(.rBracket))
    .map({ (index, tail) -> Suffix in
      .subs(index: index, tail: tail)
    })

  let propSuffix = (take(.dot) << take(.name))
    .map({ (name) -> Suffix in .prop(name: name) })

  lazy var assignSuffix = (take(.equal) << expr)
    .then(take(.in) << expr)
    .map({ (rhs, body) -> Suffix in .assign(rhs: rhs, body: body) })

  enum Suffix {

    case call(args: [Expr], tail: Token)

    case subs(index: Expr, tail: Token)

    case prop(name: Token)

    case assign(rhs: Expr, body: Expr)

  }

  lazy var preExpr = take(.amp).optional
    .then(namePath
            .or(intExpr)
            .or(floatExpr)
            .or(arrayExpr)
            .or(namePath)
            .or(bindingExpr)
            .or(funcExpr)
            .or((take(.lParen) << expr) >> take(.rParen)))
    .map({ (amp, expr) throws -> Expr in
      guard let head = amp else { return expr }

      guard let path = expr as? Path else {
        throw ParseError(diagnostic: Diagnostic.expectedPath(expr: expr))
      }
      return InoutExpr(
        path:  path,
        range: head.range.lowerBound ..< expr.range.upperBound)
    })

  let namePath = take(.name)
    .assemble({ (state, name) -> Expr in
      NamePath(
        name: String(name.value(in: state.source)),
        range: name.range)
    })

  let intExpr = take(.int)
    .assemble({ (state, literal) throws -> Expr in
      let string = literal.value(in: state.source)
      guard let value = Int(string) else {
        throw ParseError(
          diagnostic: Diagnostic.invalidLiteral(value: string, range: literal.range))
      }

      return IntExpr(value: value, range: literal.range)
    })

  let floatExpr = take(.int)
    .assemble({ (state, literal) throws -> Expr in
      let string = literal.value(in: state.source)
      guard let value = Double(string) else {
        throw ParseError(
          diagnostic: Diagnostic.invalidLiteral(value: string, range: literal.range))
      }

      return FloatExpr(value: value, range: literal.range)
    })

  lazy var arrayExpr = take(.lBracket)
    .then(exprList.optional)
    .then(take(.rBracket))
    .map({ (tree) -> Expr in
      let ((head, elems), tail) = tree
      return ArrayExpr(
        elems: elems ?? [],
        range: head.range.lowerBound ..< head.range.upperBound)
    })

  lazy var bindingExpr = bindingDecl
    .then(take(.equal) << expr)
    .then(take(.in) << expr)
    .map({ tree -> Expr in
      let ((decl, initializer), body) = tree
      return BindingExpr(
        decl: decl,
        initializer: initializer,
        body: body,
        range: decl.range.lowerBound ..< body.range.upperBound)
    })

  lazy var funcExpr = take(.lParen)
    .then(paramDeclList.optional)
    .then(((take(.rParen) << take(.arrow)) << sign) >> take(.lBrace))
    .then(expr)
    .then(take(.rBrace))
    .map({ (tree) -> Expr in
      let ((((head, params), output), body), tail) = tree
      return FuncExpr(
        params: params ?? [],
        output: output,
        body: body,
        range: head.range.lowerBound ..< tail.range.upperBound)
    })

  lazy var exprList = expr
    .then((take(.comma) << expr).many >> take(.comma).optional)
    .map({ (head, tail) in
      [head] + tail
    })

  let sign = ForwardParser<Sign, ParserState>()

  let typeDeclRefSign = take(.name)
    .assemble({ (state, name) -> Sign in
      TypeDeclRefSign(
        name: String(name.value(in: state.source)),
        range: name.range)
    })

  lazy var arraySign = take(.lBracket)
    .then(sign)
    .then(take(.rBracket))
    .map({ (tree) -> Sign in
      let ((head, base), tail) = tree
      return ArraySign(
        base: base,
        range: head.range.lowerBound ..< tail.range.upperBound)
    })

  lazy var funcSign = ((take(.lParen) ++ signList.optional) >> take(.rParen))
    .then(take(.arrow) << sign)
    .map({ (tree) -> Sign in
      let ((head, params), output) = tree
      return FuncSign(
        params: params ?? [],
        output: output,
        range: head.range.lowerBound ..< output.range.upperBound)
    })

  lazy var signList = sign
    .then((take(.comma) << sign).many >> take(.comma).optional)
    .map({ (head, tail) in
      [head] + tail
    })

  public init(source: String) {
    expr.define(postExpr)
    sign.define(typeDeclRefSign
                  .or(arraySign)
                  .or(funcSign)
                  .or((take(.lParen) << sign) >> take(.rParen)))
  }

  public mutating func parse(source: String, consumer: DiagnosticConsumer) -> Program? {
//    var str = "var p: Pair = Pair(2, 4) in p"
//    var sta = ParserState(source: str, tokens: Array(AnySequence({ Lexer(source: str) }))[0...])
//    print(expr.parse(sta))

    let tokens = Array(AnySequence({ Lexer(source: source) }))
    let state = ParserState(source: source, tokens: tokens[0...])

    switch program.parse(state) {
    case .success(let program, let remainder):
      if let next = remainder.tokens.first {
        let diag = Diagnostic(
          range: next.range, message: "unexpected token")
        consumer.consume(diag)
      }

      return program

    case .failure(let error):
      if let diag = error.diagnostic as? Diagnostic {
        consumer.consume(diag)
      } else {
        let diag = Diagnostic(
          range: state.source.endIndex ..< state.source.endIndex,
          message: error.diagnostic.map(String.init(describing:)) ?? "parse error")
        consumer.consume(diag)
      }
    }

    return nil
  }

}

/// The state of the parser.
struct ParserState {

  /// The source input.
  let source: String

  /// The stream.
  var tokens: ArraySlice<Token>

  /// The names of the structures that have been parsed.
  var knownStructs: Set<String> = []

}

/// A parser that consumes a single token satisfying some predicate.
struct TokenConsumer: Diesel.Parser {

  typealias Element = Token

  typealias Stream = ParserState

  /// A predicate that determines whether or not the given token should be consumed.
  let predicate: (Token) -> Bool

  func parse(_ state: ParserState) -> ParseResult<Token, ParserState> {
    guard let next = state.tokens.first else {
      return .error(diagnostic: "empty stream")
    }

    guard predicate(next) else {
      return .error(diagnostic: nil)
    }

    var newState = state
    newState.tokens = state.tokens.dropFirst()
    return .success(next, newState)
  }

}

private func take(_ kind: Token.Kind) -> TokenConsumer {
  return TokenConsumer(predicate: { $0.kind == kind })
}

private func take(where predicate: @escaping (Token) -> Bool) -> TokenConsumer {
  return TokenConsumer(predicate: predicate)
}
