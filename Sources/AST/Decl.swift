import Basic

/// A type or value declaration.
public protocol Decl {

  /// The range of the declaration in the input source.
  var range: SourceRange { get }

  /// The type of the declared symbol.
  var type: Type? { get }

  /// Accepts the given visitor.
  ///
  /// - Parameter visitor: A declaration visitor.
  mutating func accept<V>(_ visitor: inout V) -> V.DeclResult where V: DeclVisitor

}

/// A struct declaration.
public struct StructDecl: Decl {

  public var range: SourceRange

  public var type: Type?

  /// The name of the struct.
  public var name: String

  /// The properties of the struct.
  public var props: [BindingDecl]

  public init(name: String, props: [BindingDecl], range: SourceRange) {
    self.name = name
    self.props = props
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.DeclResult where V: DeclVisitor {
    visitor.visit(&self)
  }

}

/// A binding declaration.
public struct BindingDecl: Decl {

  public var range: SourceRange

  public var type: Type?

  /// The mutability of the binding.
  public var mutability: MutabilityQualifier

  /// The name of the binding.
  public var name: String

  /// The type signature of the binding.
  public var sign: Sign?

  public init(mutability: MutabilityQualifier, name: String, sign: Sign?, range: SourceRange) {
    self.mutability = mutability
    self.name = name
    self.sign = sign
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.DeclResult where V: DeclVisitor {
    visitor.visit(&self)
  }

}

/// A function parameter declaration.
public struct ParamDecl: Decl {

  public var range: SourceRange

  public var type: Type?

  /// The name of the parameter.
  public var name: String

  /// The type signature of the parameter.
  public var sign: Sign

  public init(name: String, sign: Sign, range: SourceRange) {
    self.name = name
    self.sign = sign
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.DeclResult where V: DeclVisitor {
    visitor.visit(&self)
  }

}
