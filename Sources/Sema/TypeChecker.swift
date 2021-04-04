import AST

public struct TypeChecker: DeclVisitor, ExprVisitor, PathVisitor, SignVisitor {

  public typealias DeclResult = Bool
  public typealias ExprResult = Bool
  public typealias PathResult = (mutability: MutabilityQualifier, type: Type)
  public typealias SignResult = Type

  /// A pointer to the AST context.
  private let context: UnsafeMutablePointer<Context>

  /// The struct context Δ.
  private var delta: [String: Type] = [:]

  /// The typing context Γ.
  private var gamma: [String: PathResult] = [:]

  /// The expected type of the next expression to visit.
  private var expectedType: Type?

  public init(context: UnsafeMutablePointer<Context>) {
    self.context = context
  }

  /// T-Program.
  public mutating func visit(_ program: inout Program) -> Bool {
    // Type check the struct declarations and build the struct context.
    for i in 0 ..< program.types.count {
      // Check for duplicate declarations.
      guard delta[program.types[i].name] == nil else {
        context.pointee.report(.duplicateStructDecl(decl: program.types[i]))
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
        context.pointee.report(.duplicatePropDecl(decl: decl.props[i]))
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
    return true
  }

  public mutating func visit(_ decl: inout BindingDecl) -> Bool {
    // Realize the type of the signature.
    let type = decl.sign.accept(&self)
    decl.type = type

    // Bail out if the signature has an error.
    return !type.hasError
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
    expr.type = .int
    guard (expectedType == nil) || (expectedType == .int) else {
      context.pointee.report(
        .typeError(expected: expectedType!, actual: .int, range: expr.range))
      return false
    }

    return true
  }

  /// T-ConstLit.
  public mutating func visit(_ expr: inout FloatExpr) -> Bool {
    expr.type = .float
    guard (expectedType == nil) || (expectedType == .float) else {
      context.pointee.report(
        .typeError(expected: expectedType!, actual: .float, range: expr.range))
      return false
    }

    return true
  }

  /// T-ArrayLit.
  public mutating func visit(_ expr: inout ArrayExpr) -> Bool {
    // Save the expected type, if any.
    let expected = expectedType

    // Handle empty arrays as a special case.
    guard !expr.elems.isEmpty else {
      guard case .array = expected else {
        // We don't have enough information to type the expression.
        context.pointee.report(
          .emptyArrayLiteralWithoutContext(range: expr.range))
        expr.type = .error
        return false
      }

      expr.type = expected
      return true
    }

    // Determine the expected type of each array element.
    var expectedElemType: Type?
    if case .array(let elemType) = expected {
      expectedElemType = elemType
    } else {
      expectedElemType = nil
    }

    // Type check all elements.
    var isWellTyped = true
    for i in 0 ..< expr.elems.count {
      expectedType = expectedElemType
      isWellTyped = isWellTyped && expr.elems[i].accept(&self)

      if (expectedElemType == nil) && (expr.elems[i].type != .error) {
        expectedElemType = expr.elems[i].type
      }
    }

    // Make sure the type we inferred is the same type as what was expected.
    expr.type = Type.array(elem: expectedElemType ?? .error)
    guard (expected == nil) || (expected == expr.type) else {
      context.pointee.report(
        .typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  /// T-StructLit.
  public mutating func visit(_ expr: inout StructExpr) -> Bool {
    // Save the expected type, if any.
    let expected = expectedType

    // Make sure the struct exists (this should always succeed, as `StructExpr` are created only
    // if the parser is able to find a callee that's named after the struct).
    guard case .struct(_, let props) = delta[expr.name] else { return false }

    // The number of arguments should be the same as the number of props in the struct.
    guard props.count == expr.args.count else {
      context.pointee.report(
        .invalidArgCount(expected: props.count, actual: expr.args.count, range: expr.range))
      return false
    }

    // The arguments should have the same type as the struct's properties.
    var isWellTyped = true
    for i in 0 ..< props.count {
      expectedType = props[i].type
      isWellTyped = isWellTyped && expr.args[i].accept(&self)
    }

    // Make sure the type we inferred is the same type as what was expected.
    expr.type = delta[expr.name]
    guard (expected == nil) || (expected == expr.type) else {
      context.pointee.report(
        .typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  /// T-FuncLit.
  public mutating func visit(_ expr: inout FuncExpr) -> Bool {
    // Save the current typing context.
    let oldGamma = gamma
    defer { gamma = oldGamma }

    // Save the expected type, if any.
    let expected = expectedType

    // Type check the parameters of the function.
    var isWellTyped = true
    var names : Set<String> = []
    var params: [Type] = []

    for i in 0 ..< expr.params.count {
      // Realize the parameter's signature.
      let name = expr.params[i].name
      let type = expr.params[i].sign.accept(&self)
      params.append(type)
      isWellTyped = isWellTyped && !type.hasError

      // Check for duplicate parameter declaration.
      guard !names.contains(name) else {
        context.pointee.report(.duplicateParamDecl(decl: expr.params[i]))
        continue
      }
      names.insert(name)

      // Update the typing context.
      if case .inout(let baseType) = type {
        gamma[name] = (.var, baseType)
      } else {
        gamma[name] = (.let, type)
      }
    }

    // Realize the type of the function's body.
    let outputType = expr.output.accept(&self)
    isWellTyped = isWellTyped && !outputType.hasError

    // Type check the body of the function.
    expectedType = (outputType != .error) ? outputType : nil
    isWellTyped = isWellTyped && expr.body.accept(&self)

    // Make sure the type we inferred is the same type as what was expected.
    expr.type = .func(params: params, output: outputType)
    guard (expected == nil) || (expected == expr.type) else {
      context.pointee.report(
        .typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout CallExpr) -> Bool {
    // Save the expected type, if any.
    let expected = expectedType

    // Type check the callee.
    expectedType = nil
    var isWellTyped = expr.callee.accept(&self)

    // The callee must have a function type.
    guard case .func(let params, let output) = expr.callee.type else {
      context.pointee.report(
        .callToNonFuncType(expr.callee.type ?? .error, range: expr.callee.range))
      expr.type = .error
      return false
    }

    // The number of arguments should be the same as the number of parameters.
    guard params.count == expr.args.count else {
      context.pointee.report(
        .invalidArgCount(expected: params.count, actual: expr.args.count, range: expr.range))
      expr.type = .error
      return false
    }

    // The arguments should have the same type as the parameters.
    var inoutArgs: [Path] = []
    for i in 0 ..< params.count {
      expectedType = params[i]
      isWellTyped = isWellTyped && expr.args[i].accept(&self)

      if case .inout = params[i], let path = (expr.args[i] as? InoutExpr)?.path {
        for other in inoutArgs {
          if mayOverlap(path, other) {
            context.pointee.report(.exclusiveAccessViolation(range: expr.args[i].range))
            isWellTyped = false
          }
        }
        inoutArgs.append(path)
      }
    }

    // Make sure the type we inferred is the same type as what was expected.
    expr.type = output
    guard (expected == nil) || (expected == expr.type) else {
      context.pointee.report(
        .typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout InoutExpr) -> Bool {
    // Save the expected type, if any.
    let expected = expectedType

    // Type check the base path.
    expectedType = nil
    let (mutability, baseType) = expr.path.accept(pathVisitor: &self)

    // `inout` expressions must have a mutable path.
    guard mutability == .var else {
      context.pointee.report(.immutableInout(type: baseType, range: expr.path.range))
      expr.type = .error
      return false
    }

    // Make sure the type we inferred is the same type as what was expected.
    expr.type = .inout(base: baseType)
    guard (expected == nil) || (expected == expr.type) else {
      context.pointee.report(
        .typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return !baseType.hasError
  }

  public mutating func visit(_ expr: inout BindingExpr) -> Bool {
    // Save the expected type, if any.
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
    isWellTyped = isWellTyped && expr.body.accept(&self)
    expr.type = expr.body.type

    // Make sure the type we inferred is the same type as what was expected.
    guard (expected == nil) || (expected == expr.type) else {
      context.pointee.report(
        .typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout AssignExpr) -> Bool {
    // Save the expected type, if any.
    let expected = expectedType

    // Type check the lvalue.
    expectedType = nil
    let (mutability, lvalueType) = expr.lvalue.accept(pathVisitor: &self)

    // Targets of assignments should be mutable.
    guard mutability == .var else {
      context.pointee.report(.immutableLValue(type: lvalueType, range: expr.lvalue.range))
      expr.type = .error
      return false
    }

    // Type check the value being assigned.
    expectedType = expr.lvalue.type
    var isWellTyped = expr.rvalue.accept(&self)

    // Type check the body of the expression.
    expectedType = expected
    isWellTyped = isWellTyped && expr.body.accept(&self)
    expr.type = expr.body.type

    // Make sure the type we inferred is the same type as what was expected.
    guard (expected == nil) || (expected == expr.type) else {
      context.pointee.report(
        .typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return isWellTyped
  }

  public mutating func visit(_ expr: inout ErrorExpr) -> Bool {
    return false
  }

  public mutating func visit(_ expr: inout NamePath) -> Bool {
    // Save the expected type, if any.
    let expected = expectedType

    // Type check the path.
    let (_, type) = expr.accept(pathVisitor: &self)

    // Make sure the type we inferred is the same type as what was expected.
    guard (expected == nil) || (expected == expr.type) else {
      context.pointee.report(
        .typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return !type.hasError
  }

  public mutating func visit(_ expr: inout PropPath) -> Bool {
    // Save the expected type, if any.
    let expected = expectedType

    // Type check the path.
    let (_, type) = expr.accept(pathVisitor: &self)

    // Make sure the type we inferred is the same type as what was expected.
    guard (expected == nil) || (expected == expr.type) else {
      context.pointee.report(
        .typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }

    return !type.hasError
  }

  public mutating func visit(_ expr: inout ElemPath) -> Bool {
    // Save the expected type, if any.
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
      context.pointee.report(
        .typeError(expected: expected!, actual: expr.type!, range: expr.range))
      return false
    }
    return !type.hasError
  }

  // T-BindingRef.
  public mutating func visit(path: inout NamePath) -> PathResult {
    let pathMut: MutabilityQualifier

    if let pair = gamma[path.name] {
      pathMut = pair.mutability
      path.type = pair.type
    } else {
      context.pointee.report(.undefinedBinding(name: path.name, range: path.range))
      pathMut = .let
      path.type = .error
    }

    return (pathMut, path.type!)
  }

  // T-[Let|Var]ElemRef.
  public mutating func visit(path: inout ElemPath) -> PathResult {
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
        context.pointee.report(.indexingInNonArrayType(pathBaseType, range: path.range))
        pathMut = .let
        path.type = .error
      }
    } else if path.base.accept(&self) {
      // The base is an expression, for which type checking succeeded.
      pathMut = .let
      if case .array(let elemType) = path.base.type {
        path.type = elemType
      } else {
        context.pointee.report(.indexingInNonArrayType(path.base.type!, range: path.range))
        path.type = .error
      }
    } else {
      // Type checking failed deeper in the AST; we don't need to emit any diagnostic.
      pathMut = .let
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
        context.pointee.report(
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
        context.pointee.report(
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
      context.pointee.report(.undefinedType(name: sign.name, range: sign.range))
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
