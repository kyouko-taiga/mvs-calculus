import AST

extension Type {

  /// Returns whether this type is "address-only", whose instances must be manipulated indirectly.s
  var isAddressOnly: Bool {
    switch self {
    case .int, .float, .error:
      return false
    default:
      return true
    }
  }

  /// Returns whether this type is "trivial", that can copied with a mere bitwise copy.
  var isTrivial: Bool {
    switch self {
    case .int, .float, .inout, .error:
      return true
    case .struct(name: _, let props):
      return props.allSatisfy({ $0.type.isTrivial })
    case .array, .func:
      return false
    }
  }

  /// The mangled name of this type.
  var mangled: String {
    switch self {
    case .int   : return "I"
    case .float : return "F"
    case .error : return "E"

    case .inout(let base):
      let b = base.mangled
      return b + "i"

    case .array(let elem):
      let b = elem.mangled
      return b + "a"

    case .struct(let name, props: _):
      return name + String(describing: name.count) + "s"

    case .func(let params, let output):
      let ps = params
        .map({ param in param.mangled + "p" })
        .joined()
      let o = output.mangled
      return o + "o" + ps + String(describing: params.count) + "f"
    }
  }

}
