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

  public let type: Type? = .int

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

  public let type: Type? = .float

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

  public var range: SourceRange

  public var type: Type?

  /// The name of the struct being referred.
  public var name: String

  /// The arguments of the struct's properties.
  public var args: [Expr]

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

  public var range: SourceRange

  public var type: Type?

  /// The parameters of the function.
  public var params: [ParamDecl]

  /// The signature of the function's return type.
  public var output: Sign

  /// The function's body.
  public var body: Expr

  /// The free variables captured by the function.
  private var captures: [String: Type]?

  public init(params: [ParamDecl], output: Sign, body: Expr, range: SourceRange) {
    self.params = params
    self.output = output
    self.body = body
    self.range = range
  }

  /// Returns the variables captured by the function.
  public mutating func collectCaptures() -> [String: Type] {
    if let captures = self.captures {
      return captures
    }

    var collector = CaptureCollector()
    captures = collector.visit(&self)
    return captures!
  }

  /// Returns the variables captured by the function.
  ///
  /// - Parameter predicate: A closure that accept the name of the capture and returns whether it
  ///   should be excluded from the result.
  public mutating func collectCaptures(excluding predicate: (String) -> Bool) -> [String: Type] {
    return collectCaptures().filter({ !predicate($0.key) })
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// A function call.
public struct CallExpr: Expr {

  public var range: SourceRange

  public var type: Type?

  /// The callee.
  public var callee: Expr

  /// The arguments of the call.
  public var args: [Expr]

  public init(callee: Expr, args: [Expr], range: SourceRange) {
    self.callee = callee
    self.args = args
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// An infix expression.
public struct InfixExpr: Expr {

  public var range: SourceRange

  public var type: Type?

  /// The left operand.
  public var lhs: Expr

  /// The right operand.
  public var rhs: Expr

  /// The operator.
  public var oper: OperExpr

  public init(lhs: Expr, rhs: Expr, oper: OperExpr, range: SourceRange) {
    self.lhs = lhs
    self.rhs = rhs
    self.oper = oper
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// An operator expression.
public struct OperExpr: Expr {

  /// The kind of an operator.
  public enum Kind: String {

    case eq, ne
    case lt, le, ge, gt
    case add, sub, mul, div

    /// Returns the type of the operator overload given the type of its operands.
    ///
    /// - Parameter operandType: The type of the operands.
    public func type(forOperandsOfType operandType: Type) -> Type? {
      switch self {
      case .eq, .ne:
        return .func(params: [operandType, operandType], output: .int)

      case .lt, .le, .ge, .gt:
        return (operandType == .int) || (operandType == .float)
          ? .func(params: [operandType, operandType], output: .int)
          : nil

      case .add, .sub, .mul, .div:
        return (operandType == .int) || (operandType == .float)
          ? .func(params: [operandType, operandType], output: operandType)
          : nil
      }
    }

    /// Returns whether the given candidate is a suitable type for an overload of this operator.
    ///
    /// - Parameter candidate: A candidate type.
    public func mayHaveType(_ candidate: Type) -> Bool {
      // Infix operators are functions of the form (T, T) -> U.
      guard case .func(let params, output: _) = candidate else { return false }
      guard (params.count == 2) && (params[0] == params[1]) else { return false }
      return candidate == type(forOperandsOfType: params[0])
    }

  }

  public var range: SourceRange

  public var type: Type?

  /// The kind of the operator.
  public var kind: Kind

  public init(kind: Kind, range: SourceRange) {
    self.kind = kind
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// An `inout` argument.
public struct InoutExpr: Expr {

  public var range: SourceRange

  public var type: Type?

  /// The path of the `inout`ed location.
  public var path: Path

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

  public var range: SourceRange

  public var type: Type?

  /// The binding being declared.
  public var decl: BindingDecl

  /// The initializer of the binding being declared.
  public var initializer: Expr

  /// The body of the expression.
  public var body: Expr

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

/// A (potentially recursive) function binding.
public struct FuncBindingExpr: Expr {

  public var range: SourceRange

  public var type: Type?

  /// The name of the binding.
  public var name: String

  /// The function literal of the binding.
  public var literal: FuncExpr

  /// The body of the expression.
  public var body: Expr

  public init(name: String, literal: FuncExpr, body: Expr, range: SourceRange) {
    self.name = name
    self.literal = literal
    self.body = body
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// An assignment.
public struct AssignExpr: Expr {

  public var range: SourceRange

  public var type: Type?

  /// The path to which the value is being assigned.
  public var lvalue: Path

  /// The value being assigned.
  public var rvalue: Expr

  /// The body of the expression.
  public var body: Expr

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

/// A conditional expression.
public struct CondExpr: Expr {

  public var range: SourceRange

  public var type: Type?

  /// The condition of the expression.
  public var cond: Expr

  /// The sub-expression to execute if the condition holds.
  public var succ: Expr

  /// The sub-expression to execute if the condition does not hold.
  public var fail: Expr

  public init(cond: Expr, succ: Expr, fail: Expr, range: SourceRange) {
    self.cond = cond
    self.succ = succ
    self.fail = fail
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// A while expression.
public struct WhileExpr: Expr {

  public var range: SourceRange

  public var type: Type?

  /// The condition of the loop.
  public var cond: Expr

  /// The body of the loop.
  public var body: Expr

  /// The continuation of the loop.
  public var tail: Expr

  public init(cond: Expr, body: Expr, tail: Expr, range: SourceRange) {
    self.cond = cond
    self.body = body
    self.tail = tail
    self.range = range
  }

  public mutating func accept<V>(_ visitor: inout V) -> V.ExprResult where V: ExprVisitor {
    visitor.visit(&self)
  }

}

/// A cast expression.
public struct CastExpr: Expr {

  public var range: SourceRange

  public var type: Type?

  /// The value being cast.
  public var value: Expr

  /// The signature of the type to which the value is being cast.
  public var sign: Sign

  public init(value: Expr, sign: Sign, range: SourceRange) {
    self.value = value
    self.sign = sign
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
