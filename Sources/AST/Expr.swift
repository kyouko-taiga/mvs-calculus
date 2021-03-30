import Basic

/// An expression.
public protocol Expr {

  /// The range of the expression in the input source.
  var range: SourceRange { get }

  /// The type of the expression.
  var type: Type? { get }

  /// Accepts the given visitor.
  ///
  /// - Parameter visitor: An expression visitor.
  mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor

}

/// A constant integer literal.
public struct IntExpr: Expr {

  /// The value of the literal.
  public var value: Int

  public var range: SourceRange

  public var type: Type?

  public init(value: Int, range: SourceRange) {
    self.value = value
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// A constant floating-point literal.
public struct FloatExpr: Expr {

  /// The value of the literal.
  public var value: Double

  public var range: SourceRange

  public var type: Type?

  public init(value: Double, range: SourceRange) {
    self.value = value
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// An array literal.
public struct ArrayExpr: Expr {

  /// The elements of the literal.
  public var elems: [Expr]

  public var range: SourceRange

  public var type: Type?

  public init(elems: [Expr], range: SourceRange) {
    self.elems = elems
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// A structure literal.
public struct StructExpr: Expr {

  /// The name of the struct being referred.
  public var name: String

  /// The arguments of the struct's properties.
  public var args: [Expr]

  public var range: SourceRange

  public var type: Type?

  public init(name: String, args: [Expr], range: SourceRange) {
    self.name = name
    self.args = args
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// A function literal.
public struct FuncExpr: Expr {

  /// The parameters of the function.
  public var params: [ParamDecl]

  /// The signature of the function's return type.
  public var output: Sign

  /// The function's body.
  public var body: Expr

  public var range: SourceRange

  public var type: Type?

  public init(params: [ParamDecl], output: Sign, body: Expr, range: SourceRange) {
    self.params = params
    self.output = output
    self.body = body
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// A function call.
public struct CallExpr: Expr {

  /// The callee.
  public var callee: Expr

  /// The arguments of the call.
  public var args: [Expr]

  public var range: SourceRange

  public var type: Type?

  public init(callee: Expr, args: [Expr], range: SourceRange) {
    self.callee = callee
    self.args = args
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// An `inout` argument.
public struct InoutExpr: Expr {

  /// The path of the `inout`ed location.
  public var path: Path

  public var range: SourceRange

  public var type: Type?

  public init(path: Path, range: SourceRange) {
    self.path = path
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// A value binding.
public struct BindingExpr: Expr {

  /// The binding being declared.
  public var decl: BindingDecl

  /// The initializer of the binding being declared.
  public var initializer: Expr

  /// The body of the expression.
  public var body: Expr

  public var range: SourceRange

  public var type: Type?

  public init(decl: BindingDecl, initializer: Expr, body: Expr, range: SourceRange) {
    self.decl = decl
    self.initializer = initializer
    self.body = body
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// An assignment.
public struct AssignExpr: Expr {

  /// The path to which the value is being assigned.
  public var lvalue: Path

  /// The value being assigned.
  public var rvalue: Expr

  /// The body of the expression.
  public var body: Expr

  public var range: SourceRange

  public var type: Type?

  public init(lvalue: Path, rvalue: Expr, body: Expr, range: SourceRange) {
    self.lvalue = lvalue
    self.rvalue = rvalue
    self.body = body
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// An ill-formed expression that results from a failed attempt to type check the program.
public struct ErrorExpr: Expr {

  public var range: SourceRange

  public let type: Type? = .error

  public init(range: SourceRange) {
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}
