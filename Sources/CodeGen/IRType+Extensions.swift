import LLVM

extension IRType {

  /// The type of a pointer to this type.
  var ptr: PointerType {
    return PointerType(pointee: self)
  }

}

/// A type that simulates a pointer to void (void*).
let voidPtr = PointerType.toVoid
