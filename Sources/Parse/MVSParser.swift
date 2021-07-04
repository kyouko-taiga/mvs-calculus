import AST
import Basic
import Diesel

/// A parser.
public struct MVSParser {

  /// `structDecl* stmtList`
  lazy var program = (structDecl >> take(.semi)).many
    .then(stmtList)
    .map(Program.init)

  /// `structDeclHead structDeclBody`
  lazy var structDecl = structDeclHead
    .then(structDeclBody)
    .assemble({ (state, tree) -> StructDecl in
      let ((head, name), (props, tail)) = tree

      // Create the struct declaration.
      let decl = StructDecl(
        name: name,
        props: props,
        range: head.range.lowerBound ..< tail.range.upperBound)

      // Register the name of the struct, so that the parser can easily distinguish between
      // function calls and struct initialization.
      if name != "<error>" {
        state.knownStructs.insert(decl.name)
      }

      return decl
    })

  /// `'struct' name`
  lazy var structDeclHead = declHead(introducer: .struct)

  /// `'{' propDecl* '}'`
  lazy var structDeclBody = take(.lBrace)
    .then((propDecl >> take(.semi).optional).many, combine: { _, rhs in rhs })
    .catch({ (error, state) in
      state.report(error)
      return .success([], state.dropping(while: { $0.kind != .rBrace }))
    })
    .then(take(.rBrace))

  /// `( 'let' | 'var' ) name ':' sign`
  lazy var propDecl = bindingDeclHead
    .then((take(.colon) << sign).catch(errorHandler(ErrorSign.init)))
    .map({ (tree) -> BindingDecl in
      let ((head, name), sign) = tree
      return BindingDecl(
        mutability: head.kind == .let ? .let : .var,
        name: name,
        sign: sign,
        initializer: nil,
        range: head.range ..< sign.range!)
    })

  /// `( 'let' | 'var' ) name ( ':' sign )? ( '=' expr )?`
  lazy var bindingDecl = bindingDeclHead
    .then((take(.colon)  << sign.catch(errorHandler(ErrorSign.init))).optional)
    .then((take(.assign) << expr.catch(errorHandler(ErrorExpr.init))).optional)
    .map({ (tree) -> BindingDecl in
      let (((head, name), sign), initializer) = tree
      let end = (initializer?.range ?? sign?.range ?? head.range).upperBound

      return BindingDecl(
        mutability: head.kind == .let ? .let : .var,
        name: name,
        sign: sign,
        initializer: initializer,
        range: head.range.lowerBound ..< end)
    })

  /// `( 'let' | 'var' ) name`
  lazy var bindingDeclHead = (take(.let) | take(.var)).then(
    take(.name)
      .assemble({ (state, name) in String(name.value(in: state.source)) })
      .catch(errorHandler({ _ in "<error>" })))

  /// `'func' name funcExpr`
  lazy var funcDecl = (declHead(introducer: .func) ++ funcExpr)
    .map({ (tree) -> FuncDecl in
      let head = tree.0
      let literal = tree.1 as! FuncExpr
      return FuncDecl(
        name: head.1,
        literal: literal,
        range: head.0.range ..< literal.range!)
    })

  /// `paramDecl ( ',' paramDecl )*`
  lazy var paramDeclList = paramDecl
    .then((take(.comma) << paramDecl).many >> take(.comma).optional)
    .map({ (head, tail) in
      [head] + tail
    })

  /// `name ':' sign`
  lazy var paramDecl = take(.name)
    .then(take(.colon) << sign)
    .assemble({ (state, tree) -> ParamDecl in
      let (name, sign) = tree
      return ParamDecl(
        name: String(name.value(in: state.source)),
        sign: sign,
        range: name.range ..< sign.range!)
    })

  /// Creates a parser that recognizes a named declaration header.
  private func declHead(introducer: Token.Kind) -> AnyParser<(Token, String), ParserState> {
    let p = take(introducer).then(
      take(.name)
        .assemble({ (state, name) in String(name.value(in: state.source)) })
        .catch(errorHandler({ _ in "<error>" })))

    return AnyParser(p)
  }

  let expr = ForwardParser<Expr, ParserState>()

  lazy var cmpExpr = addExpr
    .then(cmpOperExpr.then(addExpr).many)
    .map({ (head, tail) -> Expr in
      tail.reduce(into: head, { (lhs, pair) in
        let (oper, rhs) = pair
        lhs = InfixExpr(lhs: lhs, rhs: rhs, oper: oper, range: lhs.range! ..< rhs.range!)
      })
    })

  lazy var addExpr = mulExpr
    .then(addOperExpr.then(mulExpr).many)
    .map({ (head, tail) -> Expr in
      tail.reduce(into: head, { (lhs, pair) in
        let (oper, rhs) = pair
        lhs = InfixExpr(lhs: lhs, rhs: rhs, oper: oper, range: lhs.range! ..< rhs.range!)
      })
    })

  lazy var mulExpr = preExpr
    .then(mulOperExpr.then(preExpr).many)
    .map({ (head, tail) -> Expr in
      tail.reduce(into: head, { (lhs, pair) in
        let (oper, rhs) = pair
        lhs = InfixExpr(lhs: lhs, rhs: rhs, oper: oper, range: lhs.range! ..< rhs.range!)
      })
    })

  lazy var preExpr = take(.amp).optional
    .then(postExpr)
    .map({ (amp, expr) throws -> Expr in
      guard let head = amp else { return expr }

      guard let path = expr as? Path else {
        throw ParseError(diagnostic: Diagnostic.expectedPath(expr: expr))
      }
      return InoutExpr(path: path, range: head.range ..< expr.range!)
    })

  lazy var postExpr = primaryExpr
    .then(suffix.many)
    .assemble({ (state, tree) -> Expr in
      var (expr, suffixes) = tree

      for suffix in suffixes {
        switch suffix {
        case .call(let args, let tail):
          let range = expr.range! ..< tail.range

          // Check whether the expression is a struct literal, or an arbitrary function call.
          if let path = expr as? NamePath, (state.knownStructs.contains(path.name)) {
            expr = StructExpr(name: path.name, args: args, range: range)
          } else {
            expr = CallExpr(callee: expr, args: args, range: range)
          }

        case .subs(let index, let tail):
          let range = expr.range! ..< tail.range
          expr = ElemPath(base: expr, index: index, range: range)

        case .prop(let name):
          let range = expr.range! ..< name.range
          expr = PropPath(base: expr, name: String(name.value(in: state.source)), range: range)

        case .assign(let rhs, let body):
          guard let lhs = expr as? Path else {
            throw ParseError(diagnostic: Diagnostic.expectedPath(expr: expr))
          }
          let range = lhs.range! ..< body.range!
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

  lazy var assignSuffix = (take(.assign) << expr)
    .then(take(.in) << expr)
    .map({ (rhs, body) -> Suffix in .assign(rhs: rhs, body: body) })

  enum Suffix {

    case call(args: [Expr], tail: Token)

    case subs(index: Expr, tail: Token)

    case prop(name: Token)

    case assign(rhs: Expr, body: Expr)

  }

  lazy var primaryExpr = namePath
    .or(intExpr)
    .or(floatExpr)
    .or(arrayExpr)
    .or(namePath)
    .or(funcExpr)
    .or(operExpr)
    .or(blockExpr)
    .or((take(.lParen) << expr) >> take(.rParen))

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

  let floatExpr = take(.float)
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

  /// `'(' paramDeclList? ')' '->' sign '{' stmtList? '}'`
  lazy var funcExpr = take(.lParen)
    .then(paramDeclList.optional)
    .then(((take(.rParen) << take(.arrow)) << sign) >> take(.lBrace))
    .then(stmtList.optional)
    .then(take(.rBrace))
    .map({ (tree) -> Expr in
      let ((((head, params), output), body), tail) = tree
      return FuncExpr(
        name: nil,
        params: params ?? [],
        output: output,
        body: body ?? [],
        range: head.range.lowerBound ..< tail.range.upperBound)
    })

  lazy var exprList = expr
    .then((take(.comma) << expr).many >> take(.comma).optional)
    .map({ (head, tail) in
      [head] + tail
    })

  lazy var operExpr = (cmpOperExpr | addOperExpr | mulOperExpr)
    .map({ $0 as Expr })

  let cmpOperExpr = oper(kinds: [.eq, .ne, .lt, .le, .gt, .ge])

  let addOperExpr = oper(kinds: [.add, .sub])

  let mulOperExpr = oper(kinds: [.mul, .div])

  /// `'{' stmtList? '}'`
  lazy var blockExpr = take(.lBrace)
    .then(stmtList.optional)
    .then(take(.rBrace))
    .map({ (tree) -> Expr in
      let ((head, stmts), tail) = tree
      return BlockExpr(
        stmts: stmts ?? [],
        range: head.range.lowerBound ..< tail.range.upperBound)
    })

  /// `stmt ( ';' stmt )* ';'?`
  lazy var stmtList = stmt
    .then((take(.semi) << stmt).many)
    .then(take(.semi).optional)
    .map({ (tree) -> [Stmt] in
      let ((head, tail), closer) = tree

      // If the list ends with `;`, append a synthetic `Unit()` expression.
      if let closer = closer {
        let unit = StructExpr(name: "Unit", args: [], range: closer.range)
        return [head] + tail + [Stmt.expr(unit)]
      } else {
        return [head] + tail
      }
    })

  let stmt = ForwardParser<Stmt, ParserState>()

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
        range: head.range ..< output.range!)
    })

  lazy var signList = sign
    .then((take(.comma) << sign).many >> take(.comma).optional)
    .map({ (head, tail) in
      [head] + tail
    })

  lazy var inoutSign = take(.inout)
    .then(sign)
    .map({ (head, sign) -> Sign in
      InoutSign(base: sign, range: head.range ..< sign.range!)
    })

  private func errorHandler<T>(
    _ makeSubst: @escaping (SourceRange) -> T
  ) -> (ParseError, ParserState) -> ParseResult<T, ParserState> {
    return { (error, state) in
      state.report(error)
      return .success(makeSubst(state.errorRange), state)
    }
  }

  public init() {
    expr.define(cmpExpr)

    stmt.define(
      expr.map(Stmt.expr(_:))
        .or(funcDecl.map(Stmt.decl(_:)))
        .or(bindingDecl.map(Stmt.decl(_:))))

    sign.define(
      typeDeclRefSign
        .or(arraySign)
        .or(funcSign)
        .or(inoutSign)
        .or((take(.lParen) << sign) >> take(.rParen)))
  }

  public mutating func parse(source: String, diagConsumer: DiagnosticConsumer) -> Program? {
    let tokens = Array(AnySequence({ Lexer(source: source) }))
    let state = ParserState(
      source: source,
      tokens: tokens[0...],
      diagConsumer: diagConsumer)

    switch program.parse(state) {
    case .success(let program, let remainder):
      if let next = remainder.tokens.first {
        let diag = Diagnostic(
          range: next.range, message: "unexpected token")
        diagConsumer.consume(diag)
      }

      return program

    case .failure(let error):
      diagConsumer.consume(error: error, at: source.startIndex ..< source.startIndex)
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
  var knownStructs: Set<String> = ["Unit"]

  /// A diagnostic consumer.
  var diagConsumer: DiagnosticConsumer

  /// A range suitable to report an error that occurred at the current stream position.
  var errorRange: SourceRange {
    return tokens.first?.range ?? (source.endIndex ..< source.endIndex)
  }

  /// Reports the given parse error.
  func report(_ error: ParseError) {
    diagConsumer.consume(error: error, at: errorRange)
  }

  /// Returns a new state where the tokens satisfying the given predicate have been dropped.
  func dropping(while predicate: (Token) -> Bool) -> ParserState {
    var newState = self
    newState.tokens = newState.tokens.drop(while: predicate)
    return newState
  }

}

/// A parser that consumes a single token of some specified kind.
struct TokenKindConsumer: Parser {

  typealias Element = Token

  typealias Stream = ParserState

  /// The kind of the token to consume.
  let kind: Token.Kind

  func parse(_ state: ParserState) -> ParseResult<Token, ParserState> {
    guard let next = state.tokens.first else {
      return .error(
        diagnostic: Diagnostic.expectedToken(expectedKind: kind, range: state.errorRange))
    }

    guard next.kind == kind else {
      return .error(diagnostic: Diagnostic.expectedToken(expectedKind: kind, actual: next))
    }

    var newState = state
    newState.tokens = state.tokens.dropFirst()
    return .success(next, newState)
  }

}

private func take(_ kind: Token.Kind) -> TokenKindConsumer {
  return TokenKindConsumer(kind: kind)
}

extension OperExpr {

  init?(from token: Token) {
    switch token.kind {
    case .eq : self = OperExpr(kind: .eq , range: token.range)
    case .ne : self = OperExpr(kind: .ne , range: token.range)
    case .lt : self = OperExpr(kind: .lt , range: token.range)
    case .le : self = OperExpr(kind: .le , range: token.range)
    case .gt : self = OperExpr(kind: .gt , range: token.range)
    case .ge : self = OperExpr(kind: .ge , range: token.range)
    case .add: self = OperExpr(kind: .add, range: token.range)
    case .sub: self = OperExpr(kind: .sub, range: token.range)
    case .mul: self = OperExpr(kind: .mul, range: token.range)
    case .div: self = OperExpr(kind: .div, range: token.range)
    default: return nil
    }
  }

}

private func oper(kinds: Set<Token.Kind>) -> AnyParser<OperExpr, ParserState> {
  AnyParser({ state in
    guard let next = state.tokens.first else {
      return .error(
        diagnostic: Diagnostic.expectedOperator(range: state.errorRange))
    }

    guard kinds.contains(next.kind) else {
      return .error(
        diagnostic: Diagnostic.expectedOperator(range: state.errorRange))
    }

    var newState = state
    newState.tokens = state.tokens.dropFirst()
    return .success(OperExpr(from: next)!, newState)
  })

}
