import Basic

/// An in-flight diagnostic about a compilation issue.
public struct Diagnostic {

  /// The source range of the diagnostic.
  public let range: SourceRange

  /// The message of the diagnostic.
  public let message: String

  /// The level of the diagnostic.
  public let level: Level

  public init(range: SourceRange, message: String, level: Level = .error) {
    self.range = range
    self.message = message
    self.level = level
  }

  /// The severity of a diagnostic.
  public enum Level: CustomStringConvertible {

    /// An unrecoverable error that prevents compilation.
    case error

    /// An error that does not prevent compilation.
    case warning

    public var description: String {
      switch self {
      case .error   : return "error"
      case .warning : return "warning"
      }
    }

  }

}

/// A type that consumes and reports in-flight diagnostics.
public protocol DiagnosticConsumer {

  /// Consumes and reports a diagnostic.
  ///
  /// - Parameter diagnostic: A diagnostic.
  func consume(_ diagnostic: Diagnostic)

}
