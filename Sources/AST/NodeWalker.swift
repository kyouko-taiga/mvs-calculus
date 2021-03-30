/// A type that implements an "event-based" AST visitor/transformer.
public protocol NodeWalker {

  func willVisit(_ decl: Decl) -> (shouldWalk: Bool, nodeBefore: Decl)

  func didVisit(_ decl: Decl) -> (shouldContinue: Bool, nodeAfter: Decl)

  func willVisit(_ expr: Expr) -> (shouldWalk: Bool, nodeAfter: Expr)

  func didVisit(_ expr: Expr) -> (shouldContinue: Bool, nodeAfter: Expr)

  func willVisit(_ expr: Path) -> (shouldWalk: Bool, nodeAfter: Path)

  func didVisit(_ expr: Path) -> (shouldContinue: Bool, nodeAfter: Path)

  func willVisit(_ expr: Sign) -> (shouldWalk: Bool, nodeAfter: Sign)

  func didVisit(_ expr: Sign) -> (shouldContinue: Bool, nodeAfter: Sign)

}
