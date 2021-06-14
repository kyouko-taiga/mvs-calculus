/// A configuration option for code generation.
public enum EmitterMode {

  /// Generate code without optimizations.
  case debug

  /// Generate code optimized for execution.
  case release

  /// Generate code wrapped in a benchmark loop.
  case benchmark(count: Int)

}
