import LLVM

extension IRBuilder {

  /// Returns the function with the given name, building it if necessary.
  ///
  /// - Parameters:
  ///   - name: The name of the function.
  ///   - type: The type of the function.
  func getOrAddFunction(_ name: String, type: FunctionType) -> Function {
    if let fn = module.function(named: name) {
      assert(type == (fn.type as! FunctionType))
      return fn
    }

    let fn = addFunction(name, type: type)
    return fn
  }

}
