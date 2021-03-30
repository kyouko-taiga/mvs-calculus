/// A program.
public struct Program{

  /// The struct definitions of the program.
  public var types: [StructDecl]

  /// The entry point of the program.
  public var entry: Expr

  public init(types: [StructDecl], entry: Expr) {
    self.types = types
    self.entry = entry
  }

}
