import AST
import Basic

public struct TypeChecker: DeclVisitor, ExprVisitor, PathVisitor, SignVisitor {

  public typealias DeclResult = Bool
  public typealias ExprResult = Bool
  public typealias PathResult = (mutability: MutabilityQualifier, type: Type)
  public typealias SignResult = Type

  /// The struct context Δ.
  private var delta: [String: Type] = [:]

  /// The typing context Γ.
  private var gamma: [String: PathResult] = [:]

  /// The expected type of the next expression to visit.
  private var expectedType: Type?

  /// The consumer that's used to report in-flight diagnostics.
  private var diagConsumer: DiagnosticConsumer

  public init(diagConsumer: DiagnosticConsumer) {
    self.diagConsumer = diagConsumer
  }

  /// T-Program.
  public mutating func visit(_ program: inout Program) -> Bool {
    // Feed built-in declarations into the program.
    program.types.insert(StructDecl(name: "Unit", props: [], range: nil), at: 0)

    // Type check the struct declarations and build the struct context.
    for i in 0 ..< program.types.count {
      // Check for duplicate declarations.
      guard delta[program.types[i].name] == nil else {
        diagConsumer.consume(.duplicateStructDecl(decl: program.types[i]))
        return false
      }

      // Type check the declaration.
      guard visit(&program.types[i]) else {
        // Type checking failed deeper in the AST; we don't need to emit any diagnostic.
        return false
      }

      // Populate the struct context.
      delta[program.types[i].name] = program.types[i].type!
    }

    // Type check the statements of the program.
    for i in 0 ..< program.stmts.count {
      guard program.stmts[i].accept(&self) else {
        // Type checking failed deeper in the AST; we don't need to emit any diagnostic.
        return false
      }
    }

    delta = [:]
    gamma = [:]
    return true
  }

  /// T-Program, continued.
  public mutating func visit(_ decl: inout StructDecl) -> Bool {
    assert(gamma.isEmpty)
    var names: Set<String> = []
    var props: [StructProp] = []

    // Type check the properties of the struct.
    for i in 0 ..< decl.props.count {
      // Check for duplicate declarations.
      guard !names.contains(decl.props[i].name) else {
        diagConsumer.consume(.duplicatePropDecl(decl: decl.props[i]))
        return false
      }

      // Type check the declaration.
      guard visit(&decl.props[i]) else {
        // Type checking failed deeper in the AST. We don't need to emit any diagnostic.
        return false
      }

      names.insert(decl.props[i].name)
      props.append(
        StructProp(
          mutability: decl.props[i].mutability,
          name: decl.props[i].name,
          type: decl.props[i].type!))
    }

    decl.type = .struct(name: decl.name, props: props)
    gamma = [:]
    return true
  }

  public mutating func visit(_ decl: inout BindingDecl) -> Bool {
    // The binding should have at least a signature or an initializer.
    if (decl.sign == nil) && (decl.initializer == nil) {
      diagConsumer.consume(.missingAnnotation(decl: decl))
      decl.type = .error
      return false
    }

    // A binding declaration always produces a unit value.
    var isWellTyped = true
    if (expectedType != nil) && (expectedType != .unit) {
      diagConsumer.consume(.typeError(expected: expectedType!, actual: .unit, range: decl.range))
      isWellTyped = false
    }

    // Realize the type of the signature.
    let signType = decl.sign?.accept(&self)
    if signType == .error {
      isWellTyped = false
    } else {
      expectedType = signType
    }

    // Type check the initializer.
    if decl.initializer != nil {
      isWellTyped = decl.initializer!.accept(&self) && isWellTyped
    }

    decl.type = signType ?? decl.initializer?.type ?? .error
    gamma[decl.name] = (decl.mutability, decl.type!)
    return isWellTyped
  }

  public mutating func visit(_ decl: inout FuncDecl) -> Bool {
    defer { expectedType = nil }

    // A named function declaration always produces a unit value.
    var isWellTyped = true
    if (expectedType != nil) && (expectedType != .unit) {
      diagConsumer.consume(.typeError(expected: expectedType!, actual: .unit, range: decl.range))
      isWellTyped = false
    }

    // Type check the function's signature.
    decl.literal.type = visit(signOf: &decl.literal)
    guard decl.literal.type != .error else {
      return false
    }

    // Register the function's name before visiting the literal, so that it's defined recursively.
    gamma[decl.name] = (.let, decl.literal.type!)

    // Type check the function literal.
    return visit(bodyOf: &decl.literal) && isWellTyped
  }

  public mutating func visit(_ decl: inout ParamDecl) -> Bool {
    defer { expectedType = nil }

    // Realize the type of the signature.
    let type = decl.sign.accept(&self)
    decl.type = type

    // Bail out if the signature has an error.
    return !type.hasError
  }

  public mutating func visit(_ decl: inout ErrorDecl) -> Bool {
    expectedType = nil
    return false
  }

  /// T-ConstLit.
  public mutating func visit(_ expr: inout IntExpr) -> Bool {
    defer { expectedType = nil }

    expr.type = .int
    guard (expectedType == nil) || (expectedType == .int) else {
      diagConsumer.consume(.typeError(expected: expectedType!, actual: .int, range: expr.range))
      return false
    }

    return true
  }

  /// T-ConstLit.
  public mutating func visit(_ expr: inout FloatExpr) -> Bool {
    defer { expectedType = nil }

    expr.type = .float
    guard (expectedType == nil) || (expectedType == .float) else {
      diagConsumer.consume(.typeError(expected: expectedType!, actual: .float, range: expr.range))
      return false
    }

    return true
  }

  /// T-ArrayLit.
  public mutating func visit(_ expr: inout ArrayExpr) -> Bool {
    defer { expectedType = nil }

    // Handle empty arrays as a special case.
    guard !expr.elems.isEmpty else {
      guard case .array = expectedType else {
        // We don't have enough information to type the expression.
        diagConsumer.consume(.emptyArrayLiteralWithoutContext(range: expr.range))
        expr.type = .error
        return false
      }

      expr.type = expectedType
      return true
    }

    // Determine the expected type of each array element.
    var expectedElemType: Type?
    if case .array(let elemType) = expectedType {
      expectedElemType = elemType
    } else {
      expectedElemType = nil
    }

    // Save the expected type for the whole expression, if any.
    let expected = expectedType

    // Type check all elements.
    var isWellTyped = true
    for i in 0 ..< expr.elems.count {
      expectedType = expectedElemType
      isWellTyped = expr.elems[i].accept(&self) && isWellTyped

      if (expectedElemType == nil) && (expr.elems[i].type != .error) {
        expectedElemType = expr.elems[i].type
      }
    }

    // Make sure the type we inferred is the same type as what was expected.
    expr.type = Type.array(elem: expectedElemType ?? .error)
    guard (expected == nil) || (expected == expr.type) else {
      diagConsumer.consume(.typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  /// T-StructLit.
  public mutating func visit(_ expr: inout StructExpr) -> Bool {
    defer { expectedType = nil }

    // Make sure the struct exists (this should always succeed, as `StructExpr` are created only
    // if the parser is able to find a callee that's named after the struct).
    guard case .struct(_, let props) = delta[expr.name] else { return false }

    // Make sure the type we inferred is the same type as what was expected.
    expr.type = delta[expr.name]
    guard (expectedType == nil) || (expectedType == expr.type) else {
      diagConsumer.consume(
        .typeError(expected: expectedType!, actual: expr.type!, range: expr.range))
      return false
    }

    // The number of arguments should be the same as the number of props in the struct.
    guard props.count == expr.args.count else {
      diagConsumer.consume(
        .invalidArgCount(expected: props.count, actual: expr.args.count, range: expr.range))
      return false
    }

    // The arguments should have the same type as the struct's properties.
    var isWellTyped = true
    for i in 0 ..< props.count {
      expectedType = props[i].type
      isWellTyped = expr.args[i].accept(&self) && isWellTyped
    }

    return isWellTyped
  }

  /// T-FuncLit.
  public mutating func visit(_ expr: inout FuncExpr) -> Bool {
    defer { expectedType = nil }

    // Type check the function's signature.
    expr.type = visit(signOf: &expr)
    guard expr.type != .error else {
      return false
    }

    // Type check the function's body.
    return visit(bodyOf: &expr)
  }

  private mutating func visit(signOf literal: inout FuncExpr) -> Type {
    // Type check the parameters of the function literal.
    var isWellTyped = true
    var names : Set<String> = []
    var params: [Type] = []

    for i in 0 ..< literal.params.count {
      // Realize the parameter's signature.
      let name = literal.params[i].name
      let type = literal.params[i].sign.accept(&self)

      literal.params[i].type = type
      params.append(type)
      isWellTyped = !type.hasError && isWellTyped

      // Check for duplicate parameter declaration.
      if names.contains(name) {
        diagConsumer.consume(.duplicateParamDecl(decl: literal.params[i]))
      } else {
        names.insert(name)
      }
    }

    // Realize the type of the function's output.
    let outputType = literal.output.accept(&self)
    isWellTyped = !outputType.hasError && isWellTyped

    return isWellTyped
      ? .func(params: params, output: outputType)
      : .error
  }

  private mutating func visit(bodyOf literal: inout FuncExpr) -> Bool {
    // Extract the expected output type.
    guard case .func(params: _, let expectedOutputType) = literal.type else { unreachable() }

    // Handle empty statement lists.
    if literal.body.isEmpty {
      // Make sure the function is expected to return `unit`.
      guard expectedOutputType == .unit else {
        diagConsumer.consume(.missingExprInNonVoidFunc(literal: literal))
        return false
      }

      // We're done!
      return true
    }

    // Disallow mutable captures.
    let oldGamma = gamma
    for (key, value) in gamma {
      gamma[key] = (.let, value.type)
    }

    // Complete the typing context with all parameters.
    for param in literal.params {
      if case .inout(let baseType) = param.type {
        gamma[param.name] = (.var, baseType)
      } else {
        gamma[param.name] = (.let, param.type!)
      }
    }

    // Save the expected type for the whole expression, if any.
    let expected = expectedType

    // Type check the function's body.
    var isWellTyped = true
    for i in 0 ..< literal.body.count {
      // The last statement should have the type of the function's codomain.
      if i == literal.body.count - 1  {
        expectedType = expectedOutputType
      }

      isWellTyped = literal.body[i].accept(&self) && isWellTyped
    }
    gamma = oldGamma

    // Make sure the type we inferred is the same type as what was expected.
    guard (expected == nil) || (expected == literal.type) else {
      diagConsumer.consume(
        .typeError(expected: expected!, actual: literal.type!, range: literal.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout CallExpr) -> Bool {
    defer { expectedType = nil }
    let expected = expectedType

    // Type check the callee.
    expectedType = nil
    var isWellTyped = expr.callee.accept(&self)

    // The callee must have a function type.
    guard case .func(let params, let output) = expr.callee.type else {
      diagConsumer.consume(
        .callToNonFuncType(expr.callee.type ?? .error, range: expr.callee.range))
      expr.type = .error
      return false
    }

    // The number of arguments should be the same as the number of parameters.
    guard params.count == expr.args.count else {
      diagConsumer.consume(
        .invalidArgCount(expected: params.count, actual: expr.args.count, range: expr.range))
      expr.type = .error
      return false
    }

    // The arguments should have the same type as the parameters.
    var inoutArgs: [Path] = []
    for i in 0 ..< params.count {
      expectedType = params[i]
      isWellTyped = expr.args[i].accept(&self) && isWellTyped

      if case .inout = params[i], let path = (expr.args[i] as? InoutExpr)?.path {
        for other in inoutArgs {
          if mayOverlap(path, other) {
            diagConsumer.consume(.exclusiveAccessViolation(range: expr.args[i].range))
            isWellTyped = false
          }
        }
        inoutArgs.append(path)
      }
    }

    // Make sure the type we inferred is the same type as what was expected.
    expr.type = output
    guard (expected == nil) || (expected == expr.type) else {
      diagConsumer.consume(.typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout InfixExpr) -> Bool {
    defer { expectedType = nil }
    let expected = expectedType

    // Type check the both operands.
    expectedType = nil
    var isWellTyped = expr.lhs.accept(&self)
    expectedType = nil
    isWellTyped = expr.rhs.accept(&self) && isWellTyped

    // Infer the type of the operator.
    guard expr.lhs.type == expr.rhs.type else {
      diagConsumer.consume(
        .undefinedOperator(
          kind: expr.oper.kind,
          lhs: expr.lhs.type!,
          rhs: expr.rhs.type!,
          range: expr.oper.range))
      expr.type = .error
      return false
    }

    guard let operType = expr.oper.kind.type(forOperandsOfType: expr.lhs.type!) else {
      diagConsumer.consume(
        .undefinedOperator(
          kind: expr.oper.kind,
          lhs: expr.lhs.type!,
          rhs: expr.rhs.type!,
          range: expr.oper.range))
      expr.type = .error
      return false
    }

    guard case .func(params: _, output: let output) = operType else { unreachable() }
    expr.oper.type = operType
    expr.type = output
    guard (expected == nil) || (expected == expr.type) else {
      diagConsumer.consume(
        .typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout OperExpr) -> Bool {
    defer { expectedType = nil }

    guard let expected = expectedType, expr.kind.mayHaveType(expected) else {
      diagConsumer.consume(.ambiguousOperatorReference(range: expr.range))
      expr.type = .error
      return false
    }

    expr.type = expected
    return true
  }

  public mutating func visit(_ expr: inout InoutExpr) -> Bool {
    defer { expectedType = nil }
    let expected = expectedType

    // Type check the base path.
    expectedType = nil
    let (mutability, baseType) = expr.path.accept(pathVisitor: &self)

    // `inout` expressions must have a mutable path.
    guard mutability == .var else {
      diagConsumer.consume(.immutableInout(type: baseType, range: expr.path.range))
      expr.type = .error
      return false
    }

    // Make sure the type we inferred is the same type as what was expected.
    expr.type = .inout(base: baseType)
    guard (expected == nil) || (expected == expr.type) else {
      diagConsumer.consume(.typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return !baseType.hasError
  }

  public mutating func visit(_ expr: inout BindingExpr) -> Bool {
    defer { expectedType = nil }
    let expected = expectedType

    // Type check the binding declaration.
    guard expr.decl.accept(&self) else {
      expr.type = .error
      return false
    }

    // Type check the initializer.
    expectedType = expr.decl.type
    var isWellTyped = expr.initializer.accept(&self)

    // Update the typing context.
    gamma[expr.decl.name] = (expr.decl.mutability, expr.decl.type!)

    // Type check the body of the expression.
    expectedType = expected
    isWellTyped = expr.body.accept(&self) && isWellTyped
    expr.type = expr.body.type

    // Make sure the type we inferred is the same type as what was expected.
    guard (expected == nil) || (expected == expr.type) else {
      diagConsumer.consume(.typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout AssignExpr) -> Bool {
    defer { expectedType = nil }
    let expected = expectedType

    // Type check the lvalue.
    expectedType = nil
    let (mutability, lvalueType) = expr.lvalue.accept(pathVisitor: &self)

    // Targets of assignments should be mutable.
    guard mutability == .var else {
      diagConsumer.consume(.immutableLValue(type: lvalueType, range: expr.lvalue.range))
      expr.type = .error
      return false
    }

    // Type check the value being assigned.
    expectedType = expr.lvalue.type
    var isWellTyped = expr.rvalue.accept(&self)

    // Type check the body of the expression.
    expectedType = expected
    isWellTyped = expr.body.accept(&self) && isWellTyped
    expr.type = expr.body.type

    // Make sure the type we inferred is the same type as what was expected.
    guard (expected == nil) || (expected == expr.type) else {
      diagConsumer.consume(.typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout ErrorExpr) -> Bool {
    return false
  }

  public mutating func visit(_ expr: inout BlockExpr) -> Bool {
    defer { expectedType = nil }
    let expected = expectedType

    // Type check all statements in scope.
    var isWellTyped = true
    for i in 0 ..< expr.stmts.count {
      isWellTyped = expr.stmts[i].accept(&self) && isWellTyped
    }

    // Make sure the type we inferred is the same type as what was expected.
    guard (expected == nil) || (expected == expr.type) else {
      diagConsumer.consume(.typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout NamePath) -> Bool {
    defer { expectedType = nil }
    let expected = expectedType

    // Type check the path.
    let (_, type) = expr.accept(pathVisitor: &self)

    // Make sure the type we inferred is the same type as what was expected.
    guard (expected == nil) || (expected == expr.type) else {
      diagConsumer.consume(.typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return !type.hasError
  }

  public mutating func visit(_ expr: inout PropPath) -> Bool {
    defer { expectedType = nil }
    let expected = expectedType

    // Type check the path.
    let (_, type) = expr.accept(pathVisitor: &self)

    // Make sure the type we inferred is the same type as what was expected.
    guard (expected == nil) || (expected == expr.type) else {
      diagConsumer.consume(.typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return !type.hasError
  }

  public mutating func visit(_ expr: inout ElemPath) -> Bool {
    defer { expectedType = nil }
    let expected = expectedType

    // Type check the path.
    let (_, type) = expr.accept(pathVisitor: &self)

    // Type check the index.
    expectedType = .int
    guard expr.index.accept(&self) else {
      return false
    }

    // Make sure the type we inferred is the same type as what was expected.
    guard (expected == nil) || (expected == expr.type) else {
      diagConsumer.consume(.typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }
    return !type.hasError
  }

  // T-BindingRef.
  public mutating func visit(path: inout NamePath) -> PathResult {
    defer { expectedType = nil }

    if let pair = gamma[path.name] {
      path.type       = pair.type
      path.mutability = pair.mutability
    } else {
      diagConsumer.consume(.undefinedBinding(name: path.name, range: path.range))
      path.type       = .error
      path.mutability = .let
    }

    return (path.mutability!, path.type!)
  }

  // T-[Let|Var]ElemRef.
  public mutating func visit(path: inout ElemPath) -> PathResult {
    defer { expectedType = nil }

    expectedType = expectedType.map({
      if case .inout(let baseType) = $0 {
        return .inout(base: .array(elem: baseType))
      } else {
        return .array(elem: $0)
      }
    })

    let pathMut: MutabilityQualifier

    if var base = path.base as? Path {
      // The base is a path; we type check it as a lvalue.
      let (pathBaseMut, pathBaseType) = base.accept(pathVisitor: &self)
      path.base = base

      if case .array(let elemType) = pathBaseType {
        pathMut = pathBaseMut
        path.type = elemType
      } else {
        diagConsumer.consume(.indexingInNonArrayType(pathBaseType, range: path.range))
        pathMut = .let
        path.type = .error
      }
    } else if path.base.accept(&self) {
      // The base is an expression, for which type checking succeeded.
      pathMut = .let
      if case .array(let elemType) = path.base.type {
        path.type = elemType
      } else {
        diagConsumer.consume(.indexingInNonArrayType(path.base.type!, range: path.range))
        path.type = .error
      }
    } else {
      // Type checking failed deeper in the AST; we don't need to emit any diagnostic.
      pathMut = .let
      path.type = .error
    }

    // Type check the index.
    expectedType = .int
    if !path.index.accept(&self) {
      path.type = .error
    }

    return (pathMut, path.type!)
  }

  // T-[Let|Var]PropRef.
  public mutating func visit(path: inout PropPath) -> PathResult {
    expectedType = nil
    let pathMut: MutabilityQualifier

    if var base = path.base as? Path {
      // The base is a path; we type check it as a lvalue.
      let (pathBaseMut, pathBaseType) = base.accept(pathVisitor: &self)
      path.base = base

      if let memberDecl = pathBaseType.member(named: path.name) {
        pathMut = min(pathBaseMut, memberDecl.mutability)
        path.type = memberDecl.type
      } else {
        diagConsumer.consume(
          .missingMember(member: path.name, in: pathBaseType, range: path.range))
        pathMut = .let
        path.type = .error
      }
    } else if path.base.accept(&self) {
      // The base is an expression, for which type checking succeeded.
      pathMut = .let
      if let memberDecl = path.base.type?.member(named: path.name) {
        path.type = memberDecl.type
      } else {
        diagConsumer.consume(
          .missingMember(member: path.name, in: path.base.type!, range: path.range))
        path.type = .error
      }
    } else {
      // Type checking failed deeper in the AST; we don't need to emit any diagnostic.
      pathMut = .let
      path.type = .error
    }

    return (pathMut, path.type!)
  }

  public mutating func visit(_ sign: inout TypeDeclRefSign) -> Type {
    // Search for the type in the struct context.
    if let type = delta[sign.name] {
      sign.type = type
      return type
    }

    // Check for built-in names.
    switch sign.name {
    case "Int"  : sign.type = .int
    case "Float": sign.type = .float
    default:
      diagConsumer.consume(.undefinedType(name: sign.name, range: sign.range))
      sign.type = .error
    }

    return sign.type!
  }

  public mutating func visit(_ sign: inout ArraySign) -> Type {
    return .array(elem: sign.base.accept(&self))
  }

  public mutating func visit(_ sign: inout FuncSign) -> Type {
    var paramTypes: [Type] = []
    for i in 0 ..< sign.params.count {
      paramTypes.append(sign.params[i].accept(&self))
    }
    let outputType = sign.output.accept(&self)

    return .func(params: paramTypes, output: outputType)
  }

  public mutating func visit(_ sign: inout InoutSign) -> Type {
    return .inout(base: sign.base.accept(&self))
  }

  public mutating func visit(_ sign: inout ErrorSign) -> Type {
    return sign.type!
  }

}
