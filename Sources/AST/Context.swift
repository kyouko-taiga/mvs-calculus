/// A structure that holds long-lived metadata about AST nodes.
public struct Context {

  /// The consumer for all in-flight diagnostics.
  public var diagConsumer: DiagnosticConsumer?

  public init() {}

  public mutating func withUnsafeMutablePointer<Result>(
    _ action: (UnsafeMutablePointer<Context>) throws -> Result
  ) rethrows -> Result {
    return try action(&self)
  }

  /// Reports an in-flight diagnostic.
  public func report(_ diag: Diagnostic) {
    diagConsumer?.consume(diag)
  }

}
