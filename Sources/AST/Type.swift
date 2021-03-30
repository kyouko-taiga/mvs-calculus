/// A semantic type.
public indirect enum Type: Hashable {

  /// The built-in integer type (a.k.a. `Int`).
  case int

  /// The built-in floating point type (a.k.a. `Float`).
  case float

  /// A (user-defined) struct type.
  case `struct`(name: String, props: [StructProp])

  /// An array type.
  ///
  /// - Parameter base: The type of each element.
  case array(base: Type)

  /// A function type.
  case `func`(params: [Type], output: Type)

  /// An `inout` type.
  case `inout`(base: Type)

  /// The type of an ill-typed AST node.
  case error

  /// Returns whether the error type occurs in this type expression.
  public var hasError: Bool {
    switch self {
    case .struct(_, let props):
      return props.contains(where: { prop in prop.type.hasError })
    case .array(let base):
      return base.hasError
    case .func(let params, let output):
      return params.contains(where: { param in param.hasError }) || output.hasError
    case .inout(let base):
      return base.hasError
    case .error:
      return true
    default:
      return false
    }
  }

}

extension Type: CustomStringConvertible {

  public var description: String {
    switch self {
    case .int                 : return "Int"
    case .float               : return "Float"
    case .struct(let name, _) : return name
    case .array(let base)     : return "[\(base)]"
    case .inout(let base)     : return "&\(base)"
    case .error               : return "<error>"

    case .func(let params, let output):
      let p = params.map(String.init(describing:)).joined(separator: ", ")
      let o = String(describing: output)
      if !o.starts(with: "[") && !o.starts(with: "(") && o.contains(" ") {
        return "(\(p)) -> (\(o))"
      } else {
        return "(\(p)) -> \(o)"
      }
    }
  }

}

/// The description of a structure's property.
public struct StructProp: Hashable {

  /// The mutability of the property.
  public let mutability: MutabilityQualifier

  /// The name of the property.
  public let name: String

  /// The type of the property.
  public let type: Type

  public init(mutability: MutabilityQualifier, name: String, type: Type) {
    self.mutability = mutability
    self.name = name
    self.type = type
  }

}
