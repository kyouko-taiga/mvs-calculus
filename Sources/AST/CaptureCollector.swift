import Basic

/// An AST visitor that gathers the variables that occur free in an expression.
struct CaptureCollector: DeclVisitor, ExprVisitor {

  typealias DeclResult = [String: Type]
  typealias ExprResult = [String: Type]

  /// The set of names that are bound.
  var boundNames: Set<String> = []

  mutating func visit(_ decl: inout StructDecl) -> DeclResult {
    // Struct declarations are never visited.
    unreachable()
  }

  mutating func visit(_ decl: inout BindingDecl) -> DeclResult {
    return [:]
  }

  mutating func visit(_ decl: inout FuncDecl) -> DeclResult {
    let oldBoundNames = boundNames
    defer { boundNames = oldBoundNames }

    boundNames.insert(decl.name)
    return decl.literal.accept(&self)
  }

  mutating func visit(_ decl: inout ParamDecl) -> DeclResult {
    // Parameter declarations are never visited.
    unreachable()
  }

  mutating func visit(_ decl: inout ErrorDecl) -> DeclResult {
    return [:]
  }

  mutating func visit(_ expr: inout IntExpr) -> ExprResult {
    return [:]
  }

  mutating func visit(_ expr: inout FloatExpr) -> ExprResult {
    return [:]
  }

  mutating func visit(_ expr: inout ArrayExpr) -> ExprResult {
    var names: ExprResult = [:]
    for i in 0 ..< expr.elems.count {
      names.merge(expr.elems[i].accept(&self), uniquingKeysWith: merge(lhs:rhs:))
    }
    return names
  }

  mutating func visit(_ expr: inout StructExpr) -> ExprResult {
    var names: ExprResult = [:]
    for i in 0 ..< expr.args.count {
      names.merge(expr.args[i].accept(&self), uniquingKeysWith: merge(lhs:rhs:))
    }
    return names
  }

  mutating func visit(_ expr: inout FuncExpr) -> ExprResult {
    let oldBoundNames = boundNames
    defer { boundNames = oldBoundNames }

    boundNames.formUnion(expr.params.map({ $0.name }))
    var names: ExprResult = [:]
    for i in 0 ..< expr.body.count {
      names.merge(expr.body[i].accept(&self), uniquingKeysWith: merge(lhs:rhs:))
    }
    return names
  }

  mutating func visit(_ expr: inout CallExpr) -> ExprResult {
    var names = expr.callee.accept(&self)
    for i in 0 ..< expr.args.count {
      names.merge(expr.args[i].accept(&self), uniquingKeysWith: merge(lhs:rhs:))
    }
    return names
  }

  mutating func visit(_ expr: inout InfixExpr) -> ExprResult {
    return expr.lhs.accept(&self)
      .merging(expr.rhs.accept(&self), uniquingKeysWith: merge(lhs:rhs:))
  }

  mutating func visit(_ expr: inout OperExpr) -> ExprResult {
    return [:]
  }

  mutating func visit(_ expr: inout InoutExpr) -> ExprResult {
    return expr.path.accept(&self)
  }

  mutating func visit(_ expr: inout BindingExpr) -> ExprResult {
    let oldBoundNames = boundNames
    defer { boundNames = oldBoundNames }

    let names = expr.initializer.accept(&self)
    boundNames.insert(expr.decl.name)
    return names.merging(expr.body.accept(&self), uniquingKeysWith: merge)
  }

  mutating func visit(_ expr: inout AssignExpr) -> ExprResult {
    return expr.lvalue.accept(&self)
      .merging(expr.rvalue.accept(&self), uniquingKeysWith: merge(lhs:rhs:))
      .merging(expr.body.accept(&self), uniquingKeysWith: merge(lhs:rhs:))
  }

  mutating func visit(_ expr: inout BlockExpr) -> ExprResult {
    var names: ExprResult = [:]
    for i in 0 ..< expr.stmts.count {
      names.merge(expr.stmts[i].accept(&self), uniquingKeysWith: merge(lhs:rhs:))
    }
    return names
  }

  mutating func visit(_ expr: inout ErrorExpr) -> ExprResult {
    return [:]
  }

  mutating func visit(_ expr: inout NamePath) -> ExprResult {
    return boundNames.contains(expr.name)
      ? [:]
      : [expr.name: expr.type!]
  }

  mutating func visit(_ expr: inout PropPath) -> ExprResult {
    return expr.base.accept(&self)
  }

  mutating func visit(_ expr: inout ElemPath) -> ExprResult {
    return expr.base.accept(&self)
      .merging(expr.index.accept(&self), uniquingKeysWith: merge(lhs:rhs:))
  }

}

private func merge(lhs: Type, rhs: Type) -> Type {
  assert(lhs == rhs)
  return lhs
}
