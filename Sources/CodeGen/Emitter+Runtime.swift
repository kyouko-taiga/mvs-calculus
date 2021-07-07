import LLVM

/// A helper to build runtime symbols.
struct Runtime {

  /// The emitter that is used to generate LLVM IR instructions.
  var emitter: Emitter

  init(emitter: Emitter) {
    self.emitter = emitter
  }

  /// The runtime's `malloc(size)` function.
  var malloc: Function {
    if let fn = emitter.module.function(named: "mvs_malloc") {
      return fn
    }

    let ty = FunctionType([IntType.int64], voidPtr)
    let fn = emitter.builder.addFunction("mvs_malloc", type: ty)
    fn.addAttribute(.nounwind , to: .function)
    return fn
  }

  /// The runtime's `free(ptr)` function.
  var free: Function {
    if let fn = emitter.module.function(named: "mvs_free") {
      return fn
    }

    let ty = FunctionType([PointerType.toVoid], voidPtr)
    let fn = emitter.builder.addFunction("mvs_free", type: ty)
    fn.addAttribute(.nounwind , to: .function)
    fn.addAttribute(.nocapture, to: .argument(0))
    return fn
  }

  /// The runtime's `print_i64` function.
  var printI64: Function {
    if let fn = emitter.module.function(named: "mvs_print_i64") {
      return fn
    }

    let ty = FunctionType([IntType.int64], VoidType())
    return emitter.builder.addFunction("mvs_print_i64", type: ty)
  }

  /// The runtime's `print_f64` function.
  var printF64: Function {
    if let fn = emitter.module.function(named: "mvs_print_f64") {
      return fn
    }

    let ty = FunctionType([FloatType.double], VoidType())
    return emitter.builder.addFunction("mvs_print_f64", type: ty)
  }

  /// The runtime's `array_init(array, elem_type, count, size)` function.
  var arrayInit: Function {
    if let fn = emitter.module.function(named: "mvs_array_init") {
      return fn
    }

    let ty = FunctionType(
      [emitter.anyArrayType.ptr, emitter.metatypeType.ptr, IntType.int64, IntType.int64],
      VoidType())
    let fn = emitter.builder.addFunction("mvs_array_init", type: ty)
    fn.addAttribute(.nounwind , to: .function)
    fn.addAttribute(.nocapture, to: .argument(0))
    fn.addAttribute(.nocapture, to: .argument(1))
    fn.addAttribute(.readonly , to: .argument(1))
    return fn
  }

  /// The runtime's `array_drop(array, elem_type)` function.
  var arrayDrop: Function {
    if let fn = emitter.module.function(named: "mvs_array_drop") {
      return fn
    }

    let ty = FunctionType([emitter.anyArrayType.ptr, emitter.metatypeType.ptr], VoidType())
    let fn = emitter.builder.addFunction("mvs_array_drop", type: ty)
    fn.addAttribute(.nounwind , to: .function)
    fn.addAttribute(.nocapture, to: .argument(0))
    fn.addAttribute(.nocapture, to: .argument(1))
    fn.addAttribute(.readonly , to: .argument(1))
    return fn
  }

  /// The runtime's `array_copy(dst, src)` function.
  var arrayCopy: Function {
    if let fn = emitter.module.function(named: "mvs_array_copy") {
      return fn
    }

    let ty = FunctionType([emitter.anyArrayType.ptr, emitter.anyArrayType.ptr], VoidType())
    let fn = emitter.builder.addFunction("mvs_array_copy", type: ty)
    fn.addAttribute(.nounwind , to: .function)
    fn.addAttribute(.nocapture, to: .argument(0))
    fn.addAttribute(.nocapture, to: .argument(1))
    fn.addAttribute(.readonly , to: .argument(1))
    return fn
  }

  /// The runtime's `array_uniq(array_dst, elem_type)` function.
  var arrayUniq: Function {
    if let fn = emitter.module.function(named: "mvs_array_uniq") {
      return fn
    }

    let arrayPtr = emitter.anyArrayType.ptr
    let ty = FunctionType([arrayPtr, emitter.metatypeType.ptr], VoidType())
    let fn = emitter.builder.addFunction("mvs_array_uniq", type: ty)
    fn.addAttribute(.nounwind , to: .function)
    fn.addAttribute(.nocapture, to: .argument(0))
    fn.addAttribute(.nocapture, to: .argument(1))
    fn.addAttribute(.readonly , to: .argument(1))
    return fn
  }

  /// The runtime's `array_equal(lhs, rhs, elem_type)` function.
  var arrayEqual: Function {
    if let fn = emitter.module.function(named: "mvs_array_equal") {
      return fn
    }

    let arrayPtr = emitter.anyArrayType.ptr
    let ty = FunctionType([arrayPtr, arrayPtr, emitter.metatypeType.ptr], IntType.int64)
    let fn = emitter.builder.addFunction("mvs_array_equal", type: ty)
    fn.addAttribute(.nounwind , to: .function)
    for i in 0 ..< 3 {
      fn.addAttribute(.nocapture, to: .argument(i))
      fn.addAttribute(.readonly , to: .argument(i))
    }
    return fn
  }

  /// The runtime's `sqrt` function.
  var sqrt: Function {
    if let fn = emitter.module.function(named: "mvs_sqrt") {
      return fn
    }

    let ty = FunctionType([FloatType.double], FloatType.double)
    let fn = emitter.builder.addFunction("mvs_sqrt", type: ty)
    fn.addAttribute(.nounwind , to: .function)
    return fn
  }

  /// The runtime's `uptime_nanoseconds()` function.
  var uptimeNanoseconds: Function {
    if let fn = emitter.module.function(named: "mvs_uptime_nanoseconds") {
      return fn
    }

    let ty = FunctionType([], FloatType.double)
    let fn = emitter.builder.addFunction("mvs_uptime_nanoseconds", type: ty)
    fn.addAttribute(.nounwind , to: .function)
    return fn
  }

}

extension Emitter {

  /// A helper to build runtime symbols.
  var runtime: Runtime { Runtime(emitter: self) }

}
