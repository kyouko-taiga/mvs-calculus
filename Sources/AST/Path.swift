import Basic

/// A path to a memory location.
public protocol Path: Expr {

  /// The root of the path.
  var root: Expr { get }

  /// The mutability of the path.
  var mutability: MutabilityQualifier? { get }

  /// Returns whether this path is statically known to denote the same location as another path.
  ///
  /// - Important: The method assumes that both paths are in the same lexical scope, i.e., that all
  ///   names are bound to the same declaration.
  ///
  /// - Parameter other: Another path.
  /// - Returns: `true` if this path and `other` are lvalues statically known to denote the same
  ///   location; otherwise, `false`.
  func denotesSameLocation(as other: Path) -> Bool

  /// Accepts the given visitor.
  ///
  /// - Parameter visitor: An expression visitor.
  mutating func accept<V>(pathVisitor visitor: inout V) -> V.PathResult where V: PathVisitor

}

/// A name path.
public struct NamePath: Path {

  /// The name of the binding being referred.
  public var name: String

  public var range: SourceRange?

  public var type: Type?

  public var root: Expr { self }

  public var mutability: MutabilityQualifier?

  public init(name: String, range: SourceRange?) {
    self.name = name
    self.range = range
  }

  public func denotesSameLocation(as other: Path) -> Bool {
    guard let rPath = other as? NamePath else { return false }
    return name == rPath.name
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

  public var range: SourceRange?

  public var type: Type?

  public var root: Expr {
    return (base as? Path)?.root ?? base
  }

  public var mutability: MutabilityQualifier? {
    return (base as? Path)?.mutability ?? .let
  }

  public init(base: Expr, name: String, range: SourceRange?) {
    self.base = base
    self.name = name
    self.range = range
  }

  public func denotesSameLocation(as other: Path) -> Bool {
    guard let rPath = other as? PropPath,
          let rBase = rPath.base as? Path,
          let lBase = base as? Path
    else { return false }

    return (name == rPath.name) && lBase.denotesSameLocation(as: rBase)
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

  public var range: SourceRange?

  public var type: Type?

  public var root: Expr {
    return (base as? Path)?.root ?? base
  }

  public var mutability: MutabilityQualifier? {
    return (base as? Path)?.mutability ?? .let
  }

  public init(base: Expr, index: Expr, range: SourceRange?) {
    self.base = base
    self.index = index
    self.range = range
  }

  public func denotesSameLocation(as other: Path) -> Bool {
    guard let rPath = other as? ElemPath,
          let rBase = rPath.base as? Path,
          let lBase = base as? Path
    else { return false }

    guard let lIndex = index as? IntExpr,
          let rIndex = index as? IntExpr
    else { return false }

    return (lIndex.value == rIndex.value) && lBase.denotesSameLocation(as: rBase)
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
