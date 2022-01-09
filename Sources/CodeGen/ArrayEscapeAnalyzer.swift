import AST

/// An AST visitor that determines whether an array binding escapes its scope.
struct ArrayEscapeAnalzyer: ExprVisitor {

  typealias ExprResult = Bool

  /// The name of the array binding to analyze.
  let name: String

  mutating func visit(_ expr: inout IntExpr) -> Bool {
    return false
  }

  mutating func visit(_ expr: inout FloatExpr) -> Bool {
    return false
  }

  mutating func visit(_ expr: inout ArrayExpr) -> Bool {
    for i in 0 ..< expr.elems.count {
      if expr.elems[i].accept(&self) {
        return true
      }
    }

    return false
  }

  mutating func visit(_ expr: inout StructExpr) -> Bool {
    for i in 0 ..< expr.args.count {
      if expr.args[i].accept(&self) {
        return true
      }
    }

    return false
  }

  mutating func visit(_ expr: inout FuncExpr) -> Bool {
    let captures = expr.collectCaptures()
    return captures[name] != nil
  }

  mutating func visit(_ expr: inout CallExpr) -> Bool {
    if expr.callee.accept(&self) {
      return true
    }

    for i in 0 ..< expr.args.count {
      if expr.args[i].accept(&self) {
        return true
      }
    }

    return false
  }

  mutating func visit(_ expr: inout InfixExpr) -> Bool {
    return expr.lhs.accept(&self)
        || expr.rhs.accept(&self)
  }

  mutating func visit(_ expr: inout OperExpr) -> Bool {
    return false
  }

  mutating func visit(_ expr: inout InoutExpr) -> Bool {
    return expr.path.accept(&self)
  }

  mutating func visit(_ expr: inout BindingExpr) -> Bool {
    if expr.initializer.accept(&self) {
      return true
    }

    return (expr.decl.name != name) && expr.body.accept(&self)
  }

  mutating func visit(_ expr: inout FuncBindingExpr) -> Bool {
    return (expr.name != name)
        && (expr.body.accept(&self) || expr.literal.accept(&self))
  }

  mutating func visit(_ expr: inout AssignExpr) -> Bool {
    return expr.lvalue.accept(&self)
        || expr.rvalue.accept(&self)
        || expr.body.accept(&self)
  }

  mutating func visit(_ expr: inout CondExpr) -> Bool {
    return expr.cond.accept(&self)
        || expr.succ.accept(&self)
        || expr.fail.accept(&self)
  }

  mutating func visit(_ expr: inout WhileExpr) -> Bool {
    return expr.cond.accept(&self)
        || expr.body.accept(&self)
        || expr.tail.accept(&self)
  }

  mutating func visit(_ expr: inout CastExpr) -> Bool {
    return expr.value.accept(&self)
  }

  mutating func visit(_ expr: inout ErrorExpr) -> Bool {
    return false
  }

  mutating func visit(_ expr: inout NamePath) -> Bool {
    return expr.name == name
  }

  mutating func visit(_ expr: inout PropPath) -> Bool {
    return expr.base.accept(&self)
  }

  mutating func visit(_ expr: inout ElemPath) -> Bool {
    if expr.base is NamePath {
      return false
    }

    return expr.base.accept(&self)
        || expr.index.accept(&self)
  }

}
