/// A mutability qualifier.
public enum MutabilityQualifier: Hashable, Comparable {

  case `let`

  case `var`

  public static func < (lhs: MutabilityQualifier, rhs: MutabilityQualifier) -> Bool {
    return (lhs == .let) && (rhs == .var)
  }

}
