import Basic

/// A type signature.
public protocol Sign {

  /// The range of the type signature in the input source.
  var range: SourceRange { get }

  /// The type denoted by the signature.
  var type: Type? { get }

  /// Accepts the given visitor.
  ///
  /// - Parameter visitor: A signature visitor.
  mutating func accept<V>(_ visitor: inout V) -> V.SignResult where V: SignVisitor

}

/// A reference to named type.
public struct TypeDeclRefSign: Sign {

  public var range: SourceRange

  public var type: Type?

  /// The name of the type being referred.
  public var name: String

  public init(name: String, range: SourceRange) {
    self.name = name
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.SignResult where V: SignVisitor {
    visitor.visit(&self)
  }

}

/// The signature of an array type.
public struct ArraySign: Sign {

  public var range: SourceRange

  public var type: Type?

  /// The type signature of the array's elements.
  public var base: Sign

  public init(base: Sign, range: SourceRange) {
    self.base = base
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.SignResult where V: SignVisitor {
    visitor.visit(&self)
  }

}

/// The signature of a function type.
public struct FuncSign: Sign {

  public var range: SourceRange

  public var type: Type?

  /// The signatures of the function's parameters.
  public var params: [Sign]

  /// The signature of the function's return type.
  public var output: Sign

  public init(params: [Sign], output: Sign, range: SourceRange) {
    self.params = params
    self.output = output
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.SignResult where V: SignVisitor {
    visitor.visit(&self)
  }

}

/// The signature of an `inout` type.
public struct InoutSign: Sign {

  public var range: SourceRange

  public var type: Type?

  /// The signature of the `inout`ed type.
  public var base: Sign

  public init(base: Sign, range: SourceRange) {
    self.base = base
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.SignResult where V: SignVisitor {
    visitor.visit(&self)
  }

}

/// An ill-formed type signature.
public struct ErrorSign: Sign {

  public var range: SourceRange

  public let type: Type? = .error

  public init(range: SourceRange) {
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.SignResult where V: SignVisitor {
    visitor.visit(&self)
  }

}
