import Diesel

infix operator ++: BitwiseShiftPrecedence

/// A parser that assembles the result(s) of one or multiple parsers.
public struct AssembleParser<Base, Element>: Parser where Base: Parser {

  /// The base parser.
  private let base: Base

  /// The assembling function.
  private let assemble: (inout Base.Stream, Base.Element) throws -> Element

  public init(
    _ base: Base,
    assemble: @escaping (inout Base.Stream, Base.Element) throws -> Element
  ) {
    self.base = base
    self.assemble = assemble
  }

  public func parse(_ stream: Base.Stream) -> ParseResult<Element, Base.Stream> {
    switch base.parse(stream) {
    case .success(let output, var remainder):
      do {
        return .success(try assemble(&remainder, output), remainder)
      } catch let error as ParseError {
        return .failure(error)
      } catch {
        return .error(diagnostic: error)
      }

    case .failure(let error):
      return .failure(error)
    }
  }

}

extension Parser {

  public func assemble<R>(
    _ fn: @escaping (inout Stream, Element) throws -> R
  ) -> AssembleParser<Self, R> {
    return AssembleParser(self, assemble: fn)
  }

  static func ++ <P>(lhs: Self, rhs: P) -> CombineParser<Self, P, (Element, P.Element)>
  where P: Parser, Stream == P.Stream
  {
    return lhs.then(rhs)
  }

  static func >> <P>(lhs: Self, rhs: P) -> CombineParser<Self, P, Element>
  where P: Parser, Stream == P.Stream
  {
    return lhs.then(rhs, combine: { lhs, _ in lhs })
  }

  static func << <P>(lhs: Self, rhs: P) -> CombineParser<Self, P, P.Element>
  where P: Parser, Stream == P.Stream
  {
    return lhs.then(rhs, combine: { _, rhs in rhs })
  }

  static func | <P>(lhs: Self, rhs: P) -> Diesel.EitherParser<Self, P>
  where P : Diesel.Parser, Self.Element == P.Element, Self.Stream == P.Stream
  {
    return lhs.or(rhs)
  }

}
