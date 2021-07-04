import Basic

/// A type or value declaration.
public protocol Decl {

  /// The range of the declaration in the input source.
  var range: SourceRange? { get }

  /// The type of the declared symbol.
  var type: Type? { get }

  /// Accepts the given visitor.
  ///
  /// - Parameter visitor: A declaration visitor.
  mutating func accept<V>(_ visitor: inout V) -> V.DeclResult where V: DeclVisitor

}

/// A struct declaration.
public struct StructDecl: Decl {

  public var range: SourceRange?

  public var type: Type?

  /// The name of the struct.
  public var name: String

  /// The properties of the struct.
  public var props: [BindingDecl]

  public init(name: String, props: [BindingDecl], range: SourceRange?, type: Type? = nil) {
    self.name = name
    self.props = props
    self.range = range
    self.type = type
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.DeclResult where V: DeclVisitor {
    visitor.visit(&self)
  }

}

/// A binding declaration.
public struct BindingDecl: Decl {

  public var range: SourceRange?

  public var type: Type?

  /// The mutability of the binding.
  public var mutability: MutabilityQualifier

  /// The name of the binding.
  public var name: String

  /// The type signature of the binding, if any.
  public var sign: Sign?

  /// The initializer of the binding being declared, if any.
  public var initializer: Expr?

  public init(
    mutability  : MutabilityQualifier,
    name        : String,
    sign        : Sign?,
    initializer : Expr?,
    range       : SourceRange
  ) {
    self.mutability = mutability
    self.name = name
    self.sign = sign
    self.initializer = initializer
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.DeclResult where V: DeclVisitor {
    visitor.visit(&self)
  }

}

/// A named function declaration.
public struct FuncDecl: Decl {

  public var range: SourceRange?

  public var type: Type? { literal.type }

  /// The name of the function.
  public var name: String

  /// The function being declared.
  public var literal: FuncExpr

  public init(name: String, literal: FuncExpr, range: SourceRange?) {
    self.name = name
    self.literal = literal
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.DeclResult where V: DeclVisitor {
    visitor.visit(&self)
  }

}

/// A function parameter declaration.
public struct ParamDecl: Decl {

  public var range: SourceRange?

  public var type: Type?

  /// The name of the parameter.
  public var name: String

  /// The type signature of the parameter.
  public var sign: Sign

  public init(name: String, sign: Sign, range: SourceRange?) {
    self.name = name
    self.sign = sign
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.DeclResult where V: DeclVisitor {
    visitor.visit(&self)
  }

}

/// An ill-formed declaration.
public struct ErrorDecl: Decl {

  public var range: SourceRange?

  public let type: Type? = .error

  public init(range: SourceRange?) {
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.DeclResult where V: DeclVisitor {
    visitor.visit(&self)
  }

}
