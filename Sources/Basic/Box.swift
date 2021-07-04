/// A boxed value.
public final class Box<T> {

  /// The value of the box.
  public var value: T

  /// Creates a new box wrapping the specified value.
  ///
  /// - Parameter value: The value to wrap.
  public init(_ value: T) {
    self.value = value
  }

}
