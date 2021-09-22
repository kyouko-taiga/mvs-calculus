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
  ///
  /// This property must be reset (i.e., set to `nil`) after each visitor.
  private var expectedType: Type?

  /// The consumer that's used to report in-flight diagnostics.
  private var diagConsumer: DiagnosticConsumer

  public init(diagConsumer: DiagnosticConsumer) {
    self.diagConsumer = diagConsumer
  }

  /// T-Program.
  public mutating func visit(_ program: inout Program) -> Bool {
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

    // Type check the entry point of the program.
    guard program.entry.accept(&self) else { return false }
    return true
  }

  /// T-Program, continued.
  public mutating func visit(_ decl: inout StructDecl) -> Bool {
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
      guard (decl.props[i].sign != nil) && visit(&decl.props[i]) else {
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
    return true
  }

  public mutating func visit(_ decl: inout BindingDecl) -> Bool {
    // Realize the type of the signature.
    let type = decl.sign?.accept(&self)
    decl.type = type

    // Bail out if the signature has an error.
    return (type == nil) || !type!.hasError
  }

  public mutating func visit(_ decl: inout ParamDecl) -> Bool {
    // Realize the type of the signature.
    let type = decl.sign.accept(&self)
    decl.type = type

    // Bail out if the signature has an error.
    return !type.hasError
  }

  /// T-ConstLit.
  public mutating func visit(_ expr: inout IntExpr) -> Bool {
    defer { expectedType = nil }

    if let expected = expectedType, expected != .int {
      diagConsumer.consume(.typeError(expected: expected, actual: .int, range: expr.range))
      return false
    } else {
      return true
    }
  }

  /// T-ConstLit.
  public mutating func visit(_ expr: inout FloatExpr) -> Bool {
    defer { expectedType = nil }

    if let expected = expectedType, expected != .float {
      diagConsumer.consume(.typeError(expected: expected, actual: .int, range: expr.range))
      return false
    } else {
      return true
    }
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

    // Save the expected type, if any.
    let expectedExprType = expectedType

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
    expr.type = .array(elem: expectedElemType ?? .error)
    guard (expectedExprType == nil) || (expectedExprType == expr.type) else {
      diagConsumer.consume(
        .typeError(expected: expectedExprType!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  /// T-StructLit.
  public mutating func visit(_ expr: inout StructExpr) -> Bool {
    // Make sure the struct exists (this should always succeed, as `StructExpr` are created only
    // if the parser is able to find a callee that's named after a struct).
    guard case .struct(_, let props) = delta[expr.name] else { unreachable() }
    defer { expectedType = nil }

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
    // Type check the signature of the function.
    expr.type = visit(signOf: &expr)

    // Type check the body of the function.
    return visit(bodyOf: &expr) && !expr.type!.hasError
  }

  public mutating func visit(_ expr: inout CallExpr) -> Bool {
    defer { expectedType = nil }

    // Save the expected type, if any.
    let expectedExprType = expectedType

    // Type check the callee.
    expectedType = nil
    var isWellTyped = expr.callee.accept(&self)

    // The callee must have a function type.
    guard case .func(let params, let output) = expr.callee.type else {
      diagConsumer.consume(.callToNonFuncType(expr.callee.type!, range: expr.callee.range))
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
    guard (expectedExprType == nil) || (expectedExprType == expr.type) else {
      diagConsumer.consume(
        .typeError(expected: expectedExprType!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout InfixExpr) -> Bool {
    defer { expectedType = nil }

    // Save the expected type, if any.
    let expectedExprType = expectedType

    // Type check the both operands.
    expectedType = nil
    var isWellTyped = expr.lhs.accept(&self)
    isWellTyped = expr.rhs.accept(&self) && isWellTyped

    // Infer the type of the operator.
    guard expr.lhs.type == expr.rhs.type else {
      diagConsumer.consume(.undefinedOperator(expr: expr))
      expr.type = .error
      return false
    }
    guard let operType = expr.oper.kind.type(forOperandsOfType: expr.lhs.type!) else {
      diagConsumer.consume(.undefinedOperator(expr: expr))
      expr.type = .error
      return false
    }

    guard case .func(params: _, output: let output) = operType else { unreachable() }
    expr.oper.type = operType
    expr.type = output
    guard (expectedExprType == nil) || (expectedExprType == expr.type) else {
      diagConsumer.consume(
        .typeError(expected: expectedExprType!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout OperExpr) -> Bool {
    defer { expectedType = nil }

    guard let exprType = expectedType, expr.kind.mayHaveType(exprType) else {
      diagConsumer.consume(.ambiguousOperatorReference(range: expr.range))
      expr.type = .error
      return false
    }

    expr.type = exprType
    return true
  }

  public mutating func visit(_ expr: inout InoutExpr) -> Bool {
    defer { expectedType = nil }

    // Save the expected type, if any.
    let expectedExprType = expectedType

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
    guard (expectedExprType == nil) || (expectedExprType == expr.type) else {
      diagConsumer.consume(
        .typeError(expected: expectedExprType!, actual: expr.type!, range: expr.range))
      return false
    }

    return !baseType.hasError
  }

  public mutating func visit(_ expr: inout BindingExpr) -> Bool {
    defer { expectedType = nil }

    // Save the expected type, if any.
    let expectedExprType = expectedType

    // Type check the binding declaration.
    expectedType = nil
    guard expr.decl.accept(&self) else {
      expr.type = .error
      return false
    }

    // Type check the initializer.
    expectedType = expr.decl.type
    var isWellTyped = expr.initializer.accept(&self)

    if expr.decl.type == nil {
      expr.decl.type = expr.initializer.type!
    }

    // Update the typing context.
    gamma[expr.decl.name] = (expr.decl.mutability, expr.decl.type!)

    // Type check the body of the expression.
    expectedType = expectedExprType
    isWellTyped = expr.body.accept(&self) && isWellTyped
    expr.type = expr.body.type

    // Restore the typing context.
    gamma[expr.decl.name] = nil

    // Make sure the type we inferred is the same type as what was expected.
    guard (expectedExprType == nil) || (expectedExprType == expr.type) else {
      diagConsumer.consume(
        .typeError(expected: expectedExprType!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout FuncBindingExpr) -> ExprResult {
    defer { expectedType = nil }

    // Save the expected type, if any.
    let expectedExprType = expectedType

    // Type check the signature of the function.
    expr.literal.type = visit(signOf: &expr.literal)

    // Type check the body of the function.
    gamma[expr.name] = (.let, expr.literal.type!)
    var isWellTyped = visit(bodyOf: &expr.literal) && !expr.literal.type!.hasError

    // Type check the body of the binding expression.
    expectedType = expectedExprType
    isWellTyped = expr.body.accept(&self) && isWellTyped
    expr.type = expr.body.type

    // Restore the typing context.
    gamma[expr.name] = nil

    // Make sure the type we inferred is the same type as what was expected.
    guard (expectedExprType == nil) || (expectedExprType == expr.type) else {
      diagConsumer.consume(
        .typeError(expected: expectedExprType!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout AssignExpr) -> Bool {
    // Save the expected type, if any.
    let expectedExprType = expectedType

    var isWellTyped: Bool
    if var lvalue = expr.lvalue as? NamePath, lvalue.name == "_" {
      // Type check the value being assigned.
      expectedType = nil
      isWellTyped = expr.rvalue.accept(&self)

      // Infer the type of the lvalue as that of the rvalue.
      lvalue.type = expr.rvalue.type
      expr.lvalue = lvalue
    } else {
      // Type check the lvalue.
      expectedType = nil
      let (mutability, type) = expr.lvalue.accept(pathVisitor: &self)
      isWellTyped = !type.hasError

      // Targets of assignments should be mutable.
      if mutability != .var {
        diagConsumer.consume(.immutableLValue(type: type, range: expr.lvalue.range))
        isWellTyped = false
      }

      // Type check the value being assigned.
      expectedType = type
      isWellTyped = expr.rvalue.accept(&self) && isWellTyped
    }

    // Type check the body of the expression.
    expectedType = expectedExprType
    isWellTyped = expr.body.accept(&self) && isWellTyped

    // Make sure the type we inferred is the same type as what was expected.
    expr.type = expr.body.type
    guard (expectedExprType == nil) || (expectedExprType == expr.type) else {
      diagConsumer.consume(
        .typeError(expected: expectedExprType!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout CondExpr) -> Bool {
    defer { expectedType = nil }

    // Save the expected type, if any.
    let expectedExprType = expectedType

    // Type check the condition.
    expectedType = .int
    var isWellTyped = expr.cond.accept(&self)

    // Type check both branches.
    expectedType = expectedExprType
    isWellTyped = expr.succ.accept(&self) && isWellTyped
    expectedType = expectedExprType ?? expr.succ.type
    isWellTyped = expr.fail.accept(&self) && isWellTyped

    // Make sure the type we inferred is the same type as what was expected.
    expr.type = expr.succ.type
    guard (expectedExprType == nil) || (expectedExprType == expr.type) else {
      diagConsumer.consume(
        .typeError(expected: expectedExprType!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout CastExpr) -> Bool {
    // Realize the type of the signature.
    let type = expr.sign.accept(&self)
    expr.type = type

    // Save the expected type, if any.
    let expectedExprType = expectedType

    // Type check the value.
    expectedType = nil
    let isWellTyped = expr.value.accept(&self)

    // The type of the value and/or that of the signature should be `Any`, or both should be the
    // exact same type. Other conversions are ill-typed.
    if expr.value.type != expr.sign.type {
      if expr.value.type != .any && expr.sign.type != .any {
        expr.type = .error
        diagConsumer.consume(
          .invalidConversion(from: expr.value.type!, to: expr.sign.type!, range: expr.range))
        return false
      }
    }

    // Make sure the type we inferred from the signature is the same type as what was expected.
    guard (expectedExprType == nil) || (expectedExprType == expr.type) else {
      diagConsumer.consume(
        .typeError(expected: expectedExprType!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout ErrorExpr) -> Bool {
    return false
  }

  public mutating func visit(_ expr: inout NamePath) -> Bool {
    defer { expectedType = nil }

    // Save the expected type, if any.
    let expectedExprType = expectedType

    // Type check the path.
    let (_, type) = expr.accept(pathVisitor: &self)

    // Make sure the type we inferred is the same type as what was expected.
    guard (expectedExprType == nil) || (expectedExprType == expr.type) else {
      diagConsumer.consume(
        .typeError(expected: expectedExprType!, actual: expr.type!, range: expr.range))
      return false
    }

    return !type.hasError
  }

  public mutating func visit(_ expr: inout PropPath) -> Bool {
    defer { expectedType = nil }

    // Save the expected type, if any.
    let expectedExprType = expectedType

    // Type check the path.
    let (_, type) = expr.accept(pathVisitor: &self)

    // Make sure the type we inferred is the same type as what was expected.
    guard (expectedExprType == nil) || (expectedExprType == expr.type) else {
      diagConsumer.consume(
        .typeError(expected: expectedExprType!, actual: expr.type!, range: expr.range))
      return false
    }

    return !type.hasError
  }

  public mutating func visit(_ expr: inout ElemPath) -> Bool {
    defer { expectedType = nil }

    // Save the expected type, if any.
    let expectedExprType = expectedType

    // Type check the path.
    let (_, type) = expr.accept(pathVisitor: &self)

    // Type check the index.
    expectedType = .int
    guard expr.index.accept(&self) else {
      return false
    }

    // Make sure the type we inferred is the same type as what was expected.
    guard (expectedExprType == nil) || (expectedExprType == expr.type) else {
      diagConsumer.consume(
        .typeError(expected: expectedExprType!, actual: expr.type!, range: expr.range))
      return false
    }
    return !type.hasError
  }

  // T-BindingRef.
  public mutating func visit(path: inout NamePath) -> PathResult {
    defer { expectedType = nil }

    // Check for user-defined symbols.
    if let pair = gamma[path.name] {
      path.type = pair.type
      path.mutability = pair.mutability
    }

    // Check for built-in symbols.
    else if path.name == "uptime" {
      path.type = .func(params: [], output: .float)
      path.mutability = .let
    } else if path.name == "sqrt" {
      path.type = .func(params: [.float], output: .float)
      path.mutability = .let
    }

    // Handle errors.
    else {
      if path.name == "_" {
        diagConsumer.consume(.invalidUseOfUnderscore(range: path.range))
      } else {
        diagConsumer.consume(.undefinedBinding(name: path.name, range: path.range))
      }

      path.type = .error
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
    case "Any"  : sign.type = .any
    case "Int"  : sign.type = .int
    case "Float": sign.type = .float
    default:
      diagConsumer.consume(.undefinedType(name: sign.name, range: sign.range))
      sign.type = .error
    }

    return sign.type!
  }

  public mutating func visit(_ sign: inout ArraySign) -> Type {
    sign.type = .array(elem: sign.base.accept(&self))
    return sign.type!
  }

  public mutating func visit(_ sign: inout FuncSign) -> Type {
    var paramTypes: [Type] = []
    for i in 0 ..< sign.params.count {
      paramTypes.append(sign.params[i].accept(&self))
    }
    let outputType = sign.output.accept(&self)

    sign.type = .func(params: paramTypes, output: outputType)
    return sign.type!
  }

  public mutating func visit(_ sign: inout InoutSign) -> Type {
    sign.type = .inout(base: sign.base.accept(&self))
    return sign.type!
  }

  public mutating func visit(_ sign: inout ErrorSign) -> Type {
    return sign.type!
  }

  /// Type checks the signature of the given function literal.
  private mutating func visit(signOf literal: inout FuncExpr) -> Type {
    // Type check the parameters of the function literal.
    var names : Set<String> = []
    var params: [Type] = []

    for i in 0 ..< literal.params.count {
      // Realize the parameter's signature.
      let name = literal.params[i].name
      let type = literal.params[i].sign.accept(&self)

      // Check for duplicate parameter declaration.
      if names.contains(name) {
        diagConsumer.consume(.duplicateParamDecl(decl: literal.params[i]))
        literal.params[i].type = .error
      } else {
        names.insert(name)
        literal.params[i].type = type
      }

      params.append(literal.params[i].type!)
    }

    // Realize the type of the function's output.
    let outputType = literal.output.accept(&self)

    return .func(params: params, output: outputType)
  }

  /// Type checks the body of the given function literal.
  ///
  /// This method must be called **after** the `visit(signOf:)` has been applied on the function
  /// literal, so that the expected type of the expression is available. The type of `literal`
  /// **must** be a function type.
  private mutating func visit(bodyOf literal: inout FuncExpr) -> Bool {
    // Save the current typing context.
    let oldGamma = gamma
    defer {
      gamma = oldGamma
      expectedType = nil
    }

    // Disallow mutable captures.
    for (key, value) in gamma {
      gamma[key] = (.let, value.type)
    }

    // Update the typing context.
    for param in literal.params {
      if case .inout(let baseType) = param.type {
        gamma[param.name] = (.var, baseType)
      } else {
        gamma[param.name] = (.let, param.type!)
      }
    }

    // Type check the body of the function.
    guard case .func(params: _, let outputType) = literal.type else { unreachable() }
    expectedType = outputType
    let isWellTyped = literal.body.accept(&self)

    return isWellTyped
  }

}
