import AST

/// Returns a Boolean value indicating whether the two given expressions may represent overlapping
/// memory locations.
///
/// - Remark: The function assumes both expressions are evaluated in the same typing context.
///
/// - Parameters:
///   - lhs: An expression.
///   - rhs: Another expression.
///
/// - Returns: `true` if both `lhs` and `rhs` denote memory locations that may overlap.
func mayOverlap(_ lhs: Expr, _ rhs: Expr) -> Bool {
  // guard let a = lhs as? Path, let b = rhs as? Path else { return false }

  switch (lhs, rhs) {
  case (let a as NamePath, let b as NamePath):
    return a.name == b.name

  case (let a as NamePath, let b as ElemPath):
    return mayOverlap(a, b.base)

  case (let a as NamePath, let b as PropPath):
    return mayOverlap(a, b.base)

  case (let a as ElemPath, let b as ElemPath):
    guard let leftIndex = a.index as? IntExpr, let rightIndex = b.index as? IntExpr else {
      return true
    }
    return leftIndex.value != rightIndex.value

  case (let a as ElemPath, let b as PropPath):
    return mayOverlap(a.base, b) || mayOverlap(a, b.base)

  case (let a as PropPath, let b as PropPath):
    return (a.name == b.name) && mayOverlap(a.base, b.base)

  case (is Path, is Path):
    return mayOverlap(rhs, lhs)

  default:
    return false
  }
}
