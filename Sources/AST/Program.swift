/// A program.
public struct Program{

  /// The struct definitions of the program.
  public var types: [StructDecl]

  /// The statements of the program.
  public var stmts: [Stmt]

  public init(types: [StructDecl], stmts: [Stmt]) {
    self.types = types
    self.stmts = stmts
  }

}
