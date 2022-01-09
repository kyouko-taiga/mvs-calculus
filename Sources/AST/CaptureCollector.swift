/// An AST visitor that gathers the variables that occur free in an expression.
struct CaptureCollector: ExprVisitor {

  typealias ExprResult = [String: Type]

  /// The set of names that are bound.
  private var boundNames: Set<String> = ["_"]

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
    return expr.body.accept(&self)
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

  mutating func visit(_ expr: inout FuncBindingExpr) -> ExprResult {
    let oldBoundNames = boundNames
    defer { boundNames = oldBoundNames }

    boundNames.insert(expr.name)
    let names = expr.literal.accept(&self)
    return names.merging(expr.body.accept(&self), uniquingKeysWith: merge)
  }

  mutating func visit(_ expr: inout AssignExpr) -> ExprResult {
    return expr.lvalue.accept(&self)
      .merging(expr.rvalue.accept(&self), uniquingKeysWith: merge(lhs:rhs:))
      .merging(expr.body.accept(&self), uniquingKeysWith: merge(lhs:rhs:))
  }

  mutating func visit(_ expr: inout CondExpr) -> ExprResult {
    return expr.cond.accept(&self)
      .merging(expr.succ.accept(&self), uniquingKeysWith: merge(lhs:rhs:))
      .merging(expr.fail.accept(&self), uniquingKeysWith: merge(lhs:rhs:))
  }

  mutating func visit(_ expr: inout WhileExpr) -> ExprResult {
    return expr.cond.accept(&self)
      .merging(expr.body.accept(&self), uniquingKeysWith: merge(lhs:rhs:))
      .merging(expr.tail.accept(&self), uniquingKeysWith: merge(lhs:rhs:))
  }

  mutating func visit(_ expr: inout CastExpr) -> ExprResult {
    return expr.value.accept(&self)
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
