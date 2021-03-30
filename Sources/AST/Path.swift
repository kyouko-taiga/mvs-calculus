import Basic

/// A path to a memory location.
public protocol Path: Expr {

  /// The root of the path.
  var root: Expr { get }

  /// Accepts the given visitor.
  ///
  /// - Parameter visitor: An expression visitor.
  mutating func accept<V>(pathVisitor visitor: inout V) -> V.PathResult where V: PathVisitor

}

/// A name path.
public struct NamePath: Path {

  /// The name of the binding being referred.
  public var name: String

  public var range: SourceRange

  public var type: Type?

  public var root: Expr { self }

  public init(name: String, range: SourceRange) {
    self.name = name
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

  public mutating func accept<V>(
    pathVisitor visitor: inout V
  ) -> V.PathResult where V: PathVisitor {
    visitor.visit(path: &self)
  }

}

/// A property path.
public struct PropPath: Path {

  /// The base expression of the path.
  public var base: Expr

  /// The name of the property being referred.
  public var name: String

  public var range: SourceRange

  public var type: Type?

  public var root: Expr {
    return (base as? Path)?.root ?? base
  }

  public init(base: Expr, name: String, range: SourceRange) {
    self.base = base
    self.name = name
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

  public mutating func accept<V>(
    pathVisitor visitor: inout V
  ) -> V.PathResult where V: PathVisitor {
    visitor.visit(path: &self)
  }

}

/// A bracketed path.
public struct ElemPath: Path {

  /// The base expression of the path.
  public var base: Expr

  /// The bracketed index.
  public var index: Expr

  public var range: SourceRange

  public var type: Type?

  public var root: Expr {
    return (base as? Path)?.root ?? base
  }

  public init(base: Expr, index: Expr, range: SourceRange) {
    self.base = base
    self.index = index
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

  public mutating func accept<V>(
    pathVisitor visitor: inout V
  ) -> V.PathResult where V: PathVisitor {
    visitor.visit(path: &self)
  }

}
