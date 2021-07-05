public typealias SourceRange = Range<String.Index>

extension Range where Bound == String.Index {

  public static func ..< (lhs: Range, rhs: Range) -> Range {
    return lhs.lowerBound ..< rhs.upperBound
  }

}
