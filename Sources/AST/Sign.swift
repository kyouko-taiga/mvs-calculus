import Basic

/// A type signature.
public protocol Sign {

  /// The type denoted by the signature.
  var type: Type? { get }

  /// The range of the type signature in the input source.
  var range: SourceRange { get }

  /// Accepts the given visitor.
  ///
  /// - Parameter visitor: A signature visitor.
  mutating func accept<V>(_ visitor: inout V) -> V.SignResult where V: SignVisitor

}

/// A reference to named type.
public struct TypeDeclRefSign: Sign {

  /// The name of the type being referred.
  public var name: String

  public var type: Type?

  public var range: SourceRange

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

  /// The type signature of the array's elements.
  public var base: Sign

  public var type: Type?

  public var range: SourceRange

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

  /// The signatures of the function's parameters.
  public var params: [Sign]

  /// The signature of the function's return type.
  public var output: Sign

  public var type: Type?

  public var range: SourceRange

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

  /// The signature of the `inout`ed type.
  public var base: Sign

  public var type: Type?

  public var range: SourceRange

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

  public let type: Type? = .error

  public var range: SourceRange

  public init(range: SourceRange) {
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.SignResult where V: SignVisitor {
    visitor.visit(&self)
  }

}
