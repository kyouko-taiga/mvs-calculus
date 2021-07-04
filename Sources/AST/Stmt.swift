import Basic

/// A statement.
public struct Stmt {

  private enum Contents {

    /// A declaration statement.
    case decl(Box<Decl>)

    /// An expression statement.
    case expr(Box<Expr>)

    /// An null case, used internally to handle in-place mutation.
    case null

  }

  /// The boxed contents of the statement.
  private var contents: Contents

  /// The range of the statement in the input source.
  public var range: SourceRange? {
    switch contents {
    case .decl(let box): return box.value.range
    case .expr(let box): return box.value.range
    case .null: unreachable()
    }
  }

  /// The type of the statement.
  public var type: Type? {
    switch contents {
    case .decl(let box): return box.value.type
    case .expr(let box): return box.value.type
    case .null: unreachable()
    }
  }

  /// Unwraps the statement as a declaration, or returns `nil` if it is an expression.
  public var asDecl: Decl? {
    if case .decl(let box) = contents {
      return box.value
    } else {
      return nil
    }
  }

  /// Unwraps the statement as an expression, or returns `nil` if it is a declaration.
  public var asExpr: Expr? {
    if case .expr(let box) = contents {
      return box.value
    } else {
      return nil
    }
  }

  /// Evaluates one of the given closures, depending on the type of the statement.
  ///
  /// - Parameters:
  ///   - transformDecl: A closure that accepts a declaration.
  ///   - transformExpr: A closure that accepts an expression.
  public mutating func modify<Result>(
    asDecl transformDecl: (inout Decl) throws -> Result,
    asExpr transformExpr: (inout Expr) throws -> Result
  ) rethrows -> Result {
    switch contents {
    case .decl(var box):
      contents = .null
      if !isKnownUniquelyReferenced(&box) {
        box = Box(box.value)
      }
      defer { contents = .decl(box) }
      return try transformDecl(&box.value)

    case .expr(var box):
      contents = .null
      if !isKnownUniquelyReferenced(&box) {
        box = Box(box.value)
      }
      defer { contents = .expr(box) }
      return try transformExpr(&box.value)

    case .null:
      unreachable()
    }
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.DeclResult
  where V: DeclVisitor & ExprVisitor, V.DeclResult == V.ExprResult
  {
    return modify(
      asDecl: { decl in decl.accept(&visitor) },
      asExpr: { expr in expr.accept(&visitor) })
  }

  public static func decl(_ d: Decl) -> Stmt {
    return Stmt(contents: .decl(Box(d)))
  }

  public static func expr(_ e: Expr) -> Stmt {
    return Stmt(contents: .expr(Box(e)))
  }

}
