import AST
import Basic
import LLVM

public struct Emitter: ExprVisitor, PathVisitor {

  public typealias ExprResult = IRValue

  public typealias PathResult = (loc: IRValue, origin: PathValueOrigin?)

  /// The value origin of a path.
  ///
  /// This is used by path visitors to indicate whether the origin of the visited path starts with
  /// an rvalue.
  public typealias PathValueOrigin = (value: IRValue, type: Type)

  /// The machine target for the generated IR.
  public let target: TargetMachine

  /// The builder that is used to generate LLVM IR instructions.
  var builder: IRBuilder!

  /// The discriminator of the next closure.
  var nextClosureID = 0

  /// The LLVM context owning the module.
  var llvm: LLVM.Context { builder.module.context }

  /// The LLVM module being generated.
  var module: Module { builder.module }

  /// The local bindings.
  var bindings: [String: IRValue] = [:]

  /// The metatypes of user-defined structures.
  var metatypes: [String: Global] = [:]

  /// The (lowered) type of a type-erared zero-initializer.
  let anyInitFuncType = FunctionType([voidPtr], VoidType())

  /// The (lowered) type of a type-erared destructor.
  let anyDropFuncType = FunctionType([voidPtr], VoidType())

  /// The (lowered) type of a type-erared copy function.
  var anyCopyFuncType = FunctionType([voidPtr, voidPtr], VoidType())

  /// The (lowered) type of a type-erared equality function.
  var anyEqualityFuncType = FunctionType([voidPtr, voidPtr], IntType.int64)

  /// The (lowered) type of a metatype.
  var metatypeType: StructType {
    if let type = module.type(named: "_Metatype") {
      return type as! StructType
    }
    return builder.createStruct(
      name : "_Metatype",
      types: [
        // The name of the type.
        IntType.int8.ptr,
        // The size (a.k.a. stride) of the type.
        IntType.int64,
        // The type-erased zero-inititiazer for instances of the type.
        anyInitFuncType.ptr,
        // The type-erased destructor for instances of the type.
        anyDropFuncType.ptr,
        // The type-erased copy function for instances of the type.
        anyCopyFuncType.ptr,
        // The type-erased equality function for instances of the type.
        anyEqualityFuncType.ptr,
      ])
  }

  /// The (lowered) type of a type-erased closure.
  var anyClosureType: StructType {
    if let type = module.type(named: "_AnyClosure") {
      return type as! StructType
    }

    let type = builder.createStruct(name : "_AnyClosure")
    type.setBody([
      // The function pointer.
      voidPtr,
      // The environment pointer.
      voidPtr,
      // The copy function.
      FunctionType([type.ptr, type.ptr], VoidType()).ptr,
      // The drop function.
      FunctionType([type.ptr], VoidType()).ptr,
      // The equality function.
      FunctionType([type.ptr, type.ptr], IntType.int64).ptr,
    ])

    return type
  }

  /// Returns the (lowered) type of a type-erased array.
  var anyArrayType: StructType {
    if let type = module.type(named: "_AnyArray") {
      return type as! StructType
    }
    return builder.createStruct(
      name : "_AnyArray",
      types: [IntType.int64, IntType.int64, PointerType(pointee: IntType.int64), voidPtr])
  }

  /// LLVM's `memset` intrinsic (i.e., `llvm.memset.p0i8.i64`).
  var memset: Intrinsic {
    return module.intrinsic(
      Intrinsic.ID.llvm_memset,
      parameters: [voidPtr, IntType.int64])!
  }

  /// LLVM's `memcpy` intrinsic (i.e., `llvm.memcpy.p0i8.p0i8.i64`).
  var memcpy: Intrinsic {
    return module.intrinsic(
      Intrinsic.ID.llvm_memcpy,
      parameters: [voidPtr, voidPtr, IntType.int64])!
  }

  /// LLVM's `memmove` intrinsic (i.e., `llvm.memmove.p0i8.p0i8.i64`).
  var memmove: Intrinsic {
    return module.intrinsic(
      Intrinsic.ID.llvm_memmove,
      parameters: [voidPtr, voidPtr, IntType.int64])!
  }

  /// Creates a new emitter.
  ///
  /// - Parameter target: The machine target for the generated IR.
  public init(target: TargetMachine? = nil) throws {
    self.target = try target ?? TargetMachine()
  }

  /// Emit the LLVM IR of the given program.
  ///
  /// - Parameters:
  ///   - program: The program for which LLVM IR is generated.
  ///   - name: The name of the module (default: `main`).
  public mutating func emit(program: inout Program, name: String = "main") throws -> Module {
    builder   = IRBuilder(module: Module(name: name))
    bindings  = [:]
    metatypes = [:]
    module.targetTriple = target.triple

    // Emit the type declarations.
    for decl in program.types {
      // Create the type.
      guard case .struct(_, let props) = decl.type else { continue }
      let irType = builder.createStruct(
        name : decl.name,
        types: props.map({ lower($0.type) }))

      // Emit the type's metatype.
      assert(metatypes[decl.name] == nil)
      metatypes[decl.name] = emit(metatypeFor: decl, irType: irType)
    }

    // Emit the program's expression.
    let main = builder.addFunction("main", type: FunctionType([], IntType.int32))
    let entry = main.appendBasicBlock(named: "entry")
    builder.positionAtEnd(of: entry)

    let value = program.entry.accept(&self)
    emitPrint(value: value, type: program.entry.type!)
    emit(drop: value, type: program.entry.type!)

    builder.buildRet(IntType.int32.constant(0))

    do {
      try module.verify()
    } catch {
      module.dump()
      print("==========")
      throw error
    }

    let pipeliner = PassPipeliner(module: module)
    pipeliner.addStandardModulePipeline("opt", optimization: .default, size: .default)
    pipeliner.execute()

    return module
  }

  // ----------------------------------------------------------------------------------------------
  // MARK: Metatypes
  // ----------------------------------------------------------------------------------------------

  func emit(metatypeFor decl: StructDecl, irType: StructType) -> Global {
    assert(builder.insertBlock == nil)
    defer { builder.clearInsertionPosition() }

    // Create a global for the type name.
    var typeName = builder.addGlobalString(name: "\(decl.name).name", value: decl.name)
    typeName.linkage = .private
    let typeNamePtr = builder.buildBitCast(typeName, type: IntType.int8.ptr)

    // Create the type's initializer and destructor (unless it is trivial).
    var initFn: Function?
    var dropFn: Function?

    if !decl.type!.isTrivial {
      // Create the type's zero-initializer.
      initFn = builder.addFunction("\(decl.name).te_init", type: anyInitFuncType)
      initFn!.linkage = .private
      initFn!.addAttribute(.alwaysinline , to: .function)

      builder.positionAtEnd(of: initFn!.appendBasicBlock(named: "entry"))
      emit(init: builder.buildBitCast(initFn!.parameters[0], type: irType.ptr), type: decl.type!)
      builder.buildRetVoid()

      // Create the type's destructor.
      dropFn = builder.addFunction("\(decl.name).te_drop", type: anyInitFuncType)
      dropFn!.linkage = .private
      dropFn!.addAttribute(.alwaysinline , to: .function)

      builder.positionAtEnd(of: dropFn!.appendBasicBlock(named: "entry"))
      emit(drop: builder.buildBitCast(dropFn!.parameters[0], type: irType.ptr), type: decl.type!)
      builder.buildRetVoid()
    }

    // Create the type's copy function.
    var copyFn = builder.addFunction("\(decl.name).te_copy", type: anyCopyFuncType)
    copyFn.linkage = .private
    copyFn.addAttribute(.alwaysinline , to: .function)

    builder.positionAtEnd(of: copyFn.appendBasicBlock(named: "entry"))
    _ = builder.buildCall(
      emit(copyFuncFor: decl, irType: irType),
      args: [
        builder.buildBitCast(copyFn.parameters[0], type: irType.ptr),
        builder.buildBitCast(copyFn.parameters[1], type: irType.ptr)
      ])
    builder.buildRetVoid()

    // Create the type's equality function.
    var equalityFn = builder.addFunction("\(decl.name).te_equal", type: anyEqualityFuncType)
    equalityFn.linkage = .private
    equalityFn.addAttribute(.alwaysinline , to: .function)

    builder.positionAtEnd(of: equalityFn.appendBasicBlock(named: "entry"))
    builder.buildRet(
      builder.buildCall(
        emit(equalityFuncFor: decl, irType: irType),
        args: [
          builder.buildBitCast(equalityFn.parameters[0], type: irType.ptr),
          builder.buildBitCast(equalityFn.parameters[1], type: irType.ptr)
        ]))

    // Create the metatype.
    return builder.addGlobal(
      "\(decl.name).Type", initializer: metatypeType.constant(
        values: [
          typeNamePtr,
          stride(of: irType),
          initFn ?? anyInitFuncType.ptr.null(),
          dropFn ?? anyDropFuncType.ptr.null(),
          copyFn,
          equalityFn,
        ]))
  }

  func emit(metatypeForArrayOf elemType: Type) -> Global {
    // Mangle the type of the array to create a name prefix.
    let prefix = "_" + Type.array(elem: elemType).mangled

    // Check if we already build this metatype.
    if let global = module.global(named: "\(prefix).Type") {
      return global
    }

    // Save the builder's current insertion block to restore at the end.
    let oldInsertBlock = builder.insertBlock
    defer { oldInsertBlock.map(builder.positionAtEnd(of:)) }

    let baseMetatype: IRValue = elemType.isTrivial
      ? metatypeType.ptr.null()
      : metatype(of: elemType)

    // Create a global for the (mangled) type name.
    var typeName = builder.addGlobalString(name: "\(prefix).name", value: prefix)
    typeName.linkage = .private
    let typeNamePtr = builder.buildBitCast(typeName, type: IntType.int8.ptr)

    // Create the type's zero-initializer.
    var initFn = builder.addFunction("\(prefix).te_init", type: anyInitFuncType)
    initFn.linkage = .private
    initFn.addAttribute(.alwaysinline , to: .function)
    do {
      builder.positionAtEnd(of: initFn.appendBasicBlock(named: "entry"))
      let receiver = builder.buildBitCast(initFn.parameters[0], type: anyArrayType.ptr)
      _ = builder.buildCall(runtime.arrayInit, args: [receiver, baseMetatype, i64(0), i64(0)])
      builder.buildRetVoid()
    }

    // Create the type's destructor.
    var dropFn = builder.addFunction("\(prefix).te_drop", type: anyInitFuncType)
    dropFn.linkage = .private
    dropFn.addAttribute(.alwaysinline , to: .function)
    do {
      builder.positionAtEnd(of: dropFn.appendBasicBlock(named: "entry"))
      let receiver = builder.buildBitCast(dropFn.parameters[0], type: anyArrayType.ptr)
      _ = builder.buildCall(runtime.arrayDrop, args: [receiver, baseMetatype])
      builder.buildRetVoid()
    }

    // Create the type's copy function.
    let copyFn = builder.addFunction("\(prefix).te_copy", type: anyCopyFuncType)
    copyFn.addAttribute(.alwaysinline , to: .function)

    builder.positionAtEnd(of: copyFn.appendBasicBlock(named: "entry"))
    emit(copy: copyFn.parameters[1], type: .array(elem: elemType), to: copyFn.parameters[0])
    builder.buildRetVoid()

    // Create the metatype.
    return builder.addGlobal(
      "\(prefix).Type", initializer: metatypeType.constant(
        values: [
          typeNamePtr,
          stride(of: anyArrayType),
          initFn,
          dropFn,
          copyFn,
          anyEqualityFuncType.ptr.null(),
        ]))
  }

  func emit(copyFuncFor decl: StructDecl, irType: StructType) -> Function {
    // Save the builder's current insertion block to restore at the end.
    let oldInsertBlock = builder.insertBlock
    defer { oldInsertBlock.map(builder.positionAtEnd(of:)) }

    let irTypePtr = irType.ptr
    var fn = builder.addFunction(
      decl.name + ".copy", type: FunctionType([irTypePtr, irTypePtr], VoidType()))
    fn.linkage = .private
    builder.positionAtEnd(of: fn.appendBasicBlock(named: "entry"))

    if decl.type!.isTrivial {
      // If the struct is trivial, then memcpy is enough.
      fn.addAttribute(.alwaysinline , to: .function)
      fn.addAttribute(.argmemonly   , to: .function)

      let dst = builder.buildBitCast(fn.parameters[0], type: voidPtr)
      let src = builder.buildBitCast(fn.parameters[1], type: voidPtr)
      _ = builder.buildCall(memcpy, args: [dst, src, stride(of: irType), IntType.int1.constant(0)])
    } else if case .struct(name: _, let props) = decl.type {
      // If the struct is not trivial, then we need to copy each property individually.
      for (i, prop) in props.enumerated() {
        let dst = builder.buildStructGEP(fn.parameters[0], type: irType, index: i)
        let src = builder.buildStructGEP(fn.parameters[1], type: irType, index: i)
        emit(copy: src, type: prop.type, to: dst)
      }
    } else {
      unreachable()
    }

    builder.buildRetVoid()
    return fn
  }

  func emit(equalityFuncFor decl: StructDecl, irType: StructType) -> Function {
    guard case .struct(name: _, let props) = decl.type else { unreachable() }

    // Save the builder's current insertion block to restore at the end.
    let oldInsertBlock = builder.insertBlock
    defer { oldInsertBlock.map(builder.positionAtEnd(of:)) }

    let irTypePtr = irType.ptr
    var fn = builder.addFunction(
      decl.name + ".equal", type: FunctionType([irTypePtr, irTypePtr], IntType.int64))
    fn.linkage = .private
    builder.positionAtEnd(of: fn.appendBasicBlock(named: "entry"))

    let neBlock = fn.appendBasicBlock(named: "ne")
    for (i, prop) in props.enumerated() {
      // Extract both operands.
      var lhs = builder.buildStructGEP(fn.parameters[0], type: irType, index: i)
      var rhs = builder.buildStructGEP(fn.parameters[1], type: irType, index: i)
      if !prop.type.isAddressOnly {
        lhs = builder.buildLoad(lhs, type: lower(prop.type))
        rhs = builder.buildLoad(rhs, type: lower(prop.type))
      }

      // Bail out if we found a difference.
      let eqBlock = fn.appendBasicBlock(named: "eq")
      let test = emitAreEqual(lhs: lhs, rhs: rhs, type: prop.type)
      builder.buildCondBr(condition: test, then: eqBlock, else: neBlock)
      builder.positionAtEnd(of: eqBlock)
    }

    builder.buildRet(i64(1))

    builder.positionAtEnd(of: neBlock)
    builder.buildRet(i64(0))
    return fn
  }

  func emit(
    dropFuncForClosure prefix: String,
    captures: [(String, Type)],
    envType: StructType?
  ) -> Function {
    // Save the builder's current insertion block to restore them at the end.
    let oldInsertBlock = builder.insertBlock!
    defer { builder.positionAtEnd(of: oldInsertBlock) }

    // Create the copy function.
    var fn = builder.addFunction(
      "\(prefix).drop", type: FunctionType([anyClosureType.ptr], VoidType()))
    fn.linkage = .private
    builder.positionAtEnd(of: fn.appendBasicBlock(named: "entry"))

    // If there's no captured environment, we're done.
    guard let envType = envType else {
      builder.buildRetVoid()
      return fn
    }

    // Get the environment.
    var rawEnv = builder.buildStructGEP(fn.parameters[0], type: anyClosureType, index: 1)
    rawEnv = builder.buildLoad(rawEnv, type: voidPtr)

    if captures.contains(where: { (_, type) in !type.isTrivial }) {
      // If some captured symbols are not trivial, then we need to drop them individually.
      let env = builder.buildBitCast(rawEnv, type: envType.ptr)

      for (i, capture) in captures.enumerated() {
        let loc = builder.buildStructGEP(env, type: envType, index: i)
        emit(drop: loc, type: capture.1)
      }
    }

    // Free the environment's memory.
    _ = builder.buildCall(runtime.free, args: [rawEnv])

    builder.buildRetVoid()
    return fn
  }

  func emit(
    copyFuncForClosure prefix: String,
    captures: [(String, Type)],
    envType: StructType?
  ) -> Function {
    // Save the builder's current insertion block to restore them at the end.
    let oldInsertBlock = builder.insertBlock!
    defer { builder.positionAtEnd(of: oldInsertBlock) }

    // Create the copy function.
    var fn = builder.addFunction(
      "\(prefix).copy", type: FunctionType([anyClosureType.ptr, anyClosureType.ptr], VoidType()))
    fn.linkage = .private
    builder.positionAtEnd(of: fn.appendBasicBlock(named: "entry"))

    // Deinitialize the target.
    emit(dropClosure: fn.parameters[0])

    // Copy the source into the target.
    let dst = builder.buildBitCast(fn.parameters[0], type: voidPtr)
    let src = builder.buildBitCast(fn.parameters[1], type: voidPtr)
    _ = builder.buildCall(
      memcpy, args: [dst, src, stride(of: anyClosureType), IntType.int1.constant(0)])

    // If there's no captured environment, we're done.
    guard let envType = envType else {
      builder.buildRetVoid()
      return fn
    }

    // Allocate a new environment for the target.
    let size = stride(of: envType)
    var dstEnv: IRValue = builder.buildCall(runtime.malloc, args: [size])

    // Get the source's environment.
    var srcEnv = builder.buildStructGEP(fn.parameters[0], type: anyClosureType, index: 1)
    srcEnv = builder.buildLoad(srcEnv, type: PointerType.toVoid)

    if captures.allSatisfy({ (_, type) in type.isTrivial }) {
      // If all captured symbols are trivial, then memcpy is enough.
      _ = builder.buildCall(memcpy, args: [dstEnv, srcEnv, size, IntType.int1.constant(0)])
    } else {
      // If some captured symbols are not trivial, then we need to copy them individually.
      dstEnv = builder.buildBitCast(dstEnv, type: envType.ptr)
      srcEnv = builder.buildBitCast(srcEnv, type: envType.ptr)

      for (i, capture) in captures.enumerated() {
        let loc = builder.buildStructGEP(dstEnv, type: envType, index: i)
        var val = builder.buildStructGEP(srcEnv, type: envType, index: i)
        if !capture.1.isAddressOnly {
          val = builder.buildLoad(val, type: lower(capture.1))
        }
        emit(copy: val, type: capture.1, to: loc)
      }
    }

    // Store the new environment.
    let envLoc = builder.buildStructGEP(fn.parameters[0], type: anyClosureType, index: 1)
    builder.buildStore(builder.buildBitCast(dstEnv, type: voidPtr), to: envLoc)

    builder.buildRetVoid()
    return fn
  }

  func emit(
    equalityFuncForClosure prefix: String,
    captures: [(String, Type)],
    envType: StructType?
  ) -> Function {
    // Save the builder's current insertion block to restore them at the end.
    let oldInsertBlock = builder.insertBlock!
    defer { builder.positionAtEnd(of: oldInsertBlock) }

    // Create the equality function.
    var fn = builder.addFunction(
      "\(prefix).equal",
      type: FunctionType([anyClosureType.ptr, anyClosureType.ptr], IntType.int64))
    fn.linkage = .private
    builder.positionAtEnd(of: fn.appendBasicBlock(named: "entry"))

    // Test whether the lifted closure pointers are equal.
    let lhsFn = builder.buildLoad(
      builder.buildStructGEP(fn.parameters[0], type: anyClosureType, index: 0), type: voidPtr)
    let rhsFn = builder.buildLoad(
      builder.buildStructGEP(fn.parameters[1], type: anyClosureType, index: 0), type: voidPtr)
    let test = builder.buildICmp(lhsFn, rhsFn, .equal)

    guard let envType = envType else {
      builder.buildRet(zext(test))
      return fn
    }

    let neBlock = fn.appendBasicBlock(named: "ne")
    let eqBlock = fn.appendBasicBlock(named: "eq")
    builder.buildCondBr(condition: test, then: eqBlock, else: neBlock)
    builder.positionAtEnd(of: eqBlock)

    // Test for environment equality, assuming environements must have the same type.
    var lhsEnv = builder.buildStructGEP(fn.parameters[0], type: anyClosureType, index: 1)
    lhsEnv = builder.buildLoad(lhsEnv, type: voidPtr)
    lhsEnv = builder.buildBitCast(lhsEnv, type: envType.ptr)

    var rhsEnv = builder.buildStructGEP(fn.parameters[1], type: anyClosureType, index: 1)
    rhsEnv = builder.buildLoad(rhsEnv, type: voidPtr)
    rhsEnv = builder.buildBitCast(rhsEnv, type: envType.ptr)

    for (i, capture) in captures.enumerated() {
      // Extract both operands.
      var lhs = builder.buildStructGEP(lhsEnv, type: envType, index: i)
      var rhs = builder.buildStructGEP(rhsEnv, type: envType, index: i)
      if !capture.1.isAddressOnly {
        lhs = builder.buildLoad(lhs, type: lower(capture.1))
        rhs = builder.buildLoad(rhs, type: lower(capture.1))
      }

      // Bail out if we found a difference.
      let eqBlock = fn.appendBasicBlock(named: "eq")
      let test = emitAreEqual(lhs: lhs, rhs: rhs, type: capture.1)
      builder.buildCondBr(condition: test, then: eqBlock, else: neBlock)
      builder.positionAtEnd(of: eqBlock)
    }

    builder.buildRet(i64(1))

    builder.positionAtEnd(of: neBlock)
    builder.buildRet(i64(0))
    return fn
  }

  // ----------------------------------------------------------------------------------------------
  // MARK: Common routines
  // ----------------------------------------------------------------------------------------------

  /// Zero-initializes the value at the given location.
  func emit(init val: IRValue, type: Type) {
    let irType: IRType
    switch type {
    case .struct: irType = lower(type)
    case .array : irType = anyArrayType
    case .func  : irType = anyClosureType
    default     : return
    }

    let size = stride(of: irType)
    let buf = builder.buildBitCast(val, type: PointerType.toVoid)
    _ = builder.buildCall(
      memset, args: [buf, IntType.int8.constant(0), size, IntType.int1.constant(0)])
  }

  /// Drops the given value.
  func emit(drop val: IRValue, type: Type) {
    switch type {
    case .array(let elemType):
      let elemMetatype: IRValue = elemType.isTrivial
        ? metatypeType.ptr.null()
        : metatype(of: elemType)
      _ = builder.buildCall(runtime.arrayDrop, args: [val, elemMetatype])

    case .func:
      emit(dropClosure: val)

    default:
      break
    }
  }

  func emit(dropClosure val: IRValue) {
    let closure = builder.buildBitCast(val, type: anyClosureType.ptr)
    var dropFn = builder.buildStructGEP(closure, type: anyClosureType, index: 3)
    dropFn = builder.buildLoad(
      dropFn, type: FunctionType([anyClosureType.ptr], VoidType()).ptr)

    let elseIB = builder.currentFunction!.appendBasicBlock(named: "else")
    let thenIB = builder.currentFunction!.appendBasicBlock(named: "then")
    builder.buildCondBr(condition: builder.buildIsNull(dropFn), then: thenIB, else: elseIB)
    builder.positionAtEnd(of: elseIB)
    _ = builder.buildCall(dropFn, args: [closure])
    builder.buildBr(thenIB)
    builder.positionAtEnd(of: thenIB)
  }

  func emit(copy val: IRValue, type: Type, to loc: IRValue) {
    switch type {
    case .int, .float:
      builder.buildStore(val, to: loc)

    case .struct(let name, _):
      if type.isTrivial {
        emit(move: val, type: type, to: loc)
      } else {
        // If the struct is not trivial, fall back to its copy function.
        let fn = module.function(named: name + ".copy")!
        _ = builder.buildCall(fn, args: [loc, val])
      }

    case .array:
      // _ = builder.buildCall(runtime.arrayCopy, args: [loc, val])
      let dst = builder.buildBitCast(loc, type: voidPtr)
      let src = builder.buildBitCast(val, type: voidPtr)
      _ = builder.buildCall(
        memcpy, args: [dst, src, stride(of: anyArrayType), IntType.int1.constant(0)])

      var counterLoc = builder.buildStructGEP(loc, type: anyArrayType, index: 2)
      counterLoc = builder.buildLoad(counterLoc, type: PointerType(pointee: IntType.int64))
      let counter = builder.buildLoad(counterLoc, type: IntType.int64)
      builder.buildStore(builder.buildAdd(counter, i64(1)), to: counterLoc)

    case .func:
      let closure = builder.buildBitCast(val, type: anyClosureType.ptr)
      var copyFn = builder.buildStructGEP(closure, type: anyClosureType, index: 2)
      copyFn = builder.buildLoad(
        copyFn, type: FunctionType([anyClosureType.ptr, anyClosureType.ptr], VoidType()).ptr)

      _ = builder.buildCall(copyFn, args: [loc, val])

    default:
      unreachable()
    }
  }

  mutating func emit(copy expr: inout Expr, to loc: IRValue) {
    // Emit the rvalue.
    let tmp = expr.accept(&self)

    // Emit the copy.
    emit(copy: tmp, type: expr.type!, to: loc)

    // Deallocate the temporary.
    emit(drop: tmp, type: expr.type!)
  }

  func emit(move val: IRValue, type: Type, to loc: IRValue) {
    let size = stride(of: lower(type))
    let dst = builder.buildBitCast(loc, type: voidPtr)
    let src = builder.buildBitCast(val, type: voidPtr)
    _ = builder.buildCall(memmove, args: [dst, src, size, IntType.int1.constant(0)])
  }

  mutating func emit(move expr: inout Expr, to loc: IRValue) {
    // Emit the rvalue.
    assert(isMovable(expr))
    let tmp = expr.accept(&self)

    // Emit the move.
    emit(move: tmp, type: expr.type!, to: loc)
  }

  func emitPrint(value: IRValue, type: Type) {
    switch type {
    case .int:
      _ = builder.buildCall(runtime.printI64, args: [value])

    case .float:
      _ = builder.buildCall(runtime.printF64, args: [value])

    default:
      break
    }
  }

  /// Emits an equality check between the two given operands.
  func emitAreEqual(lhs: IRValue, rhs: IRValue, type: Type) -> IRValue {
    switch type {
    case .int:
      return builder.buildICmp(lhs, rhs, .equal)

    case .float:
      return builder.buildFCmp(lhs, rhs, .orderedEqual)

    case .struct(let name, props: _):
      let fn = module.function(named: name + ".equal")!
      let eq = builder.buildCall(fn, args: [lhs, rhs])
      return builder.buildTrunc(eq, type: IntType.int1)

    case .func:
      let lhs = builder.buildBitCast(lhs, type: anyClosureType.ptr)
      let rhs = builder.buildBitCast(rhs, type: anyClosureType.ptr)
      let equalityFn = builder.buildLoad(
        builder.buildStructGEP(lhs, type: anyClosureType, index: 4),
        type: FunctionType([anyClosureType.ptr, anyClosureType.ptr], IntType.int64).ptr)

      return builder.buildCall(equalityFn, args: [lhs, rhs])

    default:
      // FIXME: Implement equality for user-defined data types.
      fatalError()
    }
  }

  /// Emits the application of the specified operator on the given operands.
  func emitApplyOper(
    kind: OperExpr.Kind,
    type: Type,
    lhs : IRValue,
    rhs : IRValue
  ) -> IRValue {
    guard case .func(let params, _) = type else { unreachable() }

    switch kind {
    case .eq:
      return zext(emitAreEqual(lhs: lhs, rhs: rhs, type: params[0]))

    case .ne:
      return zext(builder.buildNot(emitAreEqual(lhs: lhs, rhs: rhs, type: params[0])))

    case .lt:
      switch params[0] {
      case .int   : return zext(builder.buildICmp(lhs, rhs, .signedLessThan))
      case .float : return zext(builder.buildFCmp(lhs, rhs, .orderedLessThan))
      default     : unreachable()
      }

    case .le:
      switch params[0] {
      case .int   : return zext(builder.buildICmp(lhs, rhs, .signedLessThanOrEqual))
      case .float : return zext(builder.buildFCmp(lhs, rhs, .orderedLessThanOrEqual))
      default     : unreachable()
      }

    case .ge:
      switch params[0] {
      case .int   : return zext(builder.buildICmp(lhs, rhs, .signedGreaterThanOrEqual))
      case .float : return zext(builder.buildFCmp(lhs, rhs, .orderedGreaterThanOrEqual))
      default     : unreachable()
      }

    case .gt:
      switch params[0] {
      case .int   : return zext(builder.buildICmp(lhs, rhs, .signedGreaterThan))
      case .float : return zext(builder.buildFCmp(lhs, rhs, .orderedGreaterThan))
      default     : unreachable()
      }

    case .add:
      switch params[0] {
      case .int, .float : return builder.buildAdd(lhs, rhs)
      default           : unreachable()
      }

    case .sub:
      switch params[0] {
      case .int, .float : return builder.buildSub(lhs, rhs)
      default           : unreachable()
      }

    case .mul:
      switch params[0] {
      case .int, .float : return builder.buildMul(lhs, rhs)
      default           : unreachable()
      }

    case .div:
      switch params[0] {
      case .int, .float : return builder.buildDiv(lhs, rhs)
      default           : unreachable()
      }
    }
  }

  // ----------------------------------------------------------------------------------------------
  // MARK: Codegen
  // ----------------------------------------------------------------------------------------------

  public mutating func visit(_ expr: inout IntExpr) -> IRValue {
    return i64(expr.value)
  }

  public mutating func visit(_ expr: inout FloatExpr) -> IRValue {
    return FloatType.double.constant(expr.value)
  }

  public mutating func visit(_ expr: inout ArrayExpr) -> IRValue {
    guard case .array(let elemType) = expr.type else { unreachable() }
    let elemIRType = lower(elemType)
    let elemIRTypePtr = elemIRType.ptr

    let baseMetatype: IRValue = elemType.isTrivial
      ? metatypeType.ptr.null()
      : metatype(of: elemType)

    // Allocate the array.
    let alloca = addEntryAlloca(type: anyArrayType)
    _ = builder.buildCall(
      runtime.arrayInit,
      args: [alloca, baseMetatype, i64(expr.elems.count), stride(of: elemIRType)])

    // Get the base address of the array.
    var loc = builder.buildStructGEP(alloca, type: anyArrayType, index: 3)
    loc = builder.buildLoad(loc, type: voidPtr)
    loc = builder.buildBitCast(loc, type: elemIRTypePtr)

    // Initialize each element.
    for i in 0 ..< expr.elems.count {
      let gep = builder.buildInBoundsGEP(loc, type: elemIRType, indices: [i64(i)])
      if isMovable(expr.elems[i]) {
        emit(move: &expr.elems[i], to: gep)
      } else {
        emit(init: gep, type: elemType)
        emit(copy: &expr.elems[i], to: gep)
      }
    }

    return alloca
  }

  public mutating func visit(_ expr: inout StructExpr) -> IRValue {
    let structType = lower(expr.type!)
    assert(structType is StructType)

    // Allocate the struct.
    let alloca = addEntryAlloca(type: structType)
    emit(init: alloca, type: expr.type!)

    // Initialize each property.
    for i in 0 ..< expr.args.count {
      let field = builder.buildStructGEP(alloca, type: structType, index: i)
      if isMovable(expr.args[i]) {
        emit(move: &expr.args[i], to: field)
      } else {
        emit(init: field, type: expr.args[i].type!)
        emit(copy: &expr.args[i], to: field)
      }
    }

    return alloca
  }

  public mutating func visit(_ expr: inout FuncExpr) -> IRValue {
    guard case .func(let params, let output) = expr.type else { unreachable() }

    // Save the builder's current insertion block and bindings to restore them at the end.
    let oldInsertBlock = builder.insertBlock!
    let oldBindings = bindings
    defer {
      builder.positionAtEnd(of: oldInsertBlock)
      bindings = oldBindings
    }

    // Generate a prefix for the name of the functions we're about to emit.
    let prefix = "_closure\(nextClosureID)"
    nextClosureID += 1

    // Gathers the free variables of the function.
    var collector = CaptureCollector()
    let captures = expr.accept(&collector).sorted(by: { a, b in a.key < b.key })

    // Create the function's environment.
    let envType: StructType?
    let env: IRValue

    if captures.isEmpty {
      // No environment.
      envType = nil
      env = PointerType.toVoid.null()
    } else {
      // Create the environment type.
      envType = builder.createStruct(
        name : "\(prefix).env",
        types: captures.map({ _, type in lower(type) }))

      // Allocate the environment and copy the captured bindings.
      env = builder.buildCall(runtime.malloc, args: [stride(of: envType!)])
      let buf = builder.buildBitCast(env, type: envType!.ptr)

      for (i, capture) in captures.enumerated() {
        let loc = builder.buildStructGEP(buf, type: envType!, index: i)

        let val = capture.value.isAddressOnly
          ? bindings[capture.key]!
          : builder.buildLoad(bindings[capture.key]!, type: lower(capture.value))
        emit(copy: val, type: capture.value, to: loc)
      }
    }

    // Create the function.
    var fn = builder.addFunction("\(prefix)", type: buildFunctionType(from: params, to: output))
    fn.linkage = .private

    // Create the closure.
    let closure = addEntryAlloca(type: anyClosureType)
    builder.buildStore(
      builder.buildBitCast(fn, type: PointerType.toVoid),
      to: builder.buildStructGEP(closure, type: anyClosureType, index: 0))
    builder.buildStore(
      env,
      to: builder.buildStructGEP(closure, type: anyClosureType, index: 1))
    builder.buildStore(
      emit(copyFuncForClosure: prefix, captures: captures, envType: envType),
      to: builder.buildStructGEP(closure, type: anyClosureType, index: 2))
    builder.buildStore(
      emit(dropFuncForClosure: prefix, captures: captures, envType: envType),
      to: builder.buildStructGEP(closure, type: anyClosureType, index: 3))
    builder.buildStore(
      emit(equalityFuncForClosure: prefix, captures: captures, envType: envType),
      to: builder.buildStructGEP(closure, type: anyClosureType, index: 4))

    // Configure the local bindings.
    builder.positionAtEnd(of: fn.appendBasicBlock(named: "entry"))
    bindings = [:]
    let offset = output.isAddressOnly ? 1 : 0
    for (i, param) in expr.params.enumerated() {
      if param.type!.isAddressOnly {
        bindings[param.name] = fn.parameters[i + offset]
      } else {
        let alloca = addEntryAlloca(type: lower(param.type!))
        builder.buildStore(fn.parameters[i + offset], to: alloca)
        bindings[param.name] = alloca
      }
    }

    if let eType = envType {
      let e = builder.buildBitCast(fn.parameters.last!, type: eType.ptr)
      for (i, capture) in captures.enumerated() {
        bindings[capture.key] = builder.buildStructGEP(e, type: eType, index: i)
      }
    }

    // Emit the function.
    if output.isAddressOnly {
      emit(move: &expr.body, to: fn.parameters[0])
      builder.buildRetVoid()
    } else {
      builder.buildRet(expr.body.accept(&self))
    }

    return closure
  }

  public mutating func visit(_ expr: inout CallExpr) -> IRValue {
    guard case .func(let params, let output) = expr.callee.type else { unreachable() }

    // Emit the callee.
    let callee = builder.buildBitCast(expr.callee.accept(&self), type: anyClosureType.ptr)

    // Emit the arguments.
    var args: [IRValue] = []
    for i in 0 ..< expr.args.count {
      args.append(expr.args[i].accept(&self))
    }

    // Extract the function.
    let fnType = buildFunctionType(from: params, to: output)
    var fn = builder.buildStructGEP(callee, type: anyClosureType, index: 0)
    fn = builder.buildLoad(fn, type: PointerType.toVoid)
    fn = builder.buildBitCast(fn, type: fnType.ptr)

    // Extract the environment.
    var env = builder.buildStructGEP(callee, type: anyClosureType, index: 1)
    env = builder.buildLoad(env, type: PointerType.toVoid)

    // Emit the call.
    let result: IRValue
    if output.isAddressOnly {
      result = addEntryAlloca(type: lower(output))
      _ = builder.buildCall(fn, args: [result] + args + [env])
    } else {
      result = builder.buildCall(fn, args: args + [env])
    }

    return result
  }

  public mutating func visit(_ expr: inout InfixExpr) -> IRValue {
    let lhs = expr.lhs.accept(&self)
    let rhs = expr.rhs.accept(&self)
    return emitApplyOper(kind: expr.oper.kind, type: expr.oper.type!, lhs: lhs, rhs: rhs)
  }

  public mutating func visit(_ expr: inout OperExpr) -> IRValue {
    guard case .func(let params, let output) = expr.type else { unreachable() }

    let closure = addEntryAlloca(type: anyClosureType)

    // Attempt to retrieve the wrapper.
    let prefix = "_\(expr.kind.rawValue)\(expr.type!.mangled)"
    if let fn = module.function(named: prefix) {
      builder.buildStore(
        builder.buildBitCast(fn, type: PointerType.toVoid),
        to: builder.buildStructGEP(closure, type: anyClosureType, index: 0))
      builder.buildStore(
        PointerType.toVoid.null(),
        to: builder.buildStructGEP(closure, type: anyClosureType, index: 1))
      builder.buildStore(
        module.function(named: "\(prefix).copy")!,
        to: builder.buildStructGEP(closure, type: anyClosureType, index: 2))
      builder.buildStore(
        module.function(named: "\(prefix).drop")!,
        to: builder.buildStructGEP(closure, type: anyClosureType, index: 3))

      return closure
    }

    // Wrap the operator in a closure.
    var fn = builder.addFunction("\(prefix)", type: buildFunctionType(from: params, to: output))
    fn.linkage = .private

    builder.buildStore(
      builder.buildBitCast(fn, type: PointerType.toVoid),
      to: builder.buildStructGEP(closure, type: anyClosureType, index: 0))
    builder.buildStore(
      PointerType.toVoid.null(),
      to: builder.buildStructGEP(closure, type: anyClosureType, index: 1))
    builder.buildStore(
      emit(copyFuncForClosure: prefix, captures: [], envType: nil),
      to: builder.buildStructGEP(closure, type: anyClosureType, index: 2))
    builder.buildStore(
      emit(dropFuncForClosure: prefix, captures: [], envType: nil),
      to: builder.buildStructGEP(closure, type: anyClosureType, index: 3))

    // Emit the function.
    let oldInsertBlock = builder.insertBlock!
    defer { builder.positionAtEnd(of: oldInsertBlock) }

    builder.positionAtEnd(of: fn.appendBasicBlock(named: "entry"))
    builder.buildRet(
      emitApplyOper(
        kind: expr.kind,
        type: expr.type!,
        lhs : fn.parameters[0],
        rhs : fn.parameters[1]))

    return closure
  }

  public mutating func visit(_ expr: inout InoutExpr) -> IRValue {
    let (loc, origin) = uniquify(path: &expr.path)
    assert(origin == nil)
    return loc
  }

  public mutating func visit(_ expr: inout BindingExpr) -> IRValue {
    // If the body of the expression is the binding itself, return its value directly.
    if let path = expr.body as? NamePath, path.name == expr.decl.name {
      return expr.initializer.accept(&self)
    }

    let alloca: IRValue
    if isMovable(expr.initializer) {
      // Move the initializer's value.
      alloca = expr.initializer.accept(&self)
    } else {
      // Allocate storage for the binding.
      alloca = addEntryAlloca(type: lower(expr.decl.type!), name: expr.decl.name)
      emit(init: alloca, type: expr.decl.type!)

      // Emit the binding's value.
      emit(copy: &expr.initializer, to: alloca)
    }

    // Update the bindings.
    let oldBindings = bindings
    bindings[expr.decl.name] = alloca

    // Emit the body of the expression.
    let body = expr.body.accept(&self)

    // Deinitialize the binding's value.
    emit(drop: alloca, type: expr.initializer.type!)

    // Restore the bindings.
    bindings = oldBindings
    return body
  }


  public mutating func visit(_ expr: inout AssignExpr) -> IRValue {
    // Emit the location, applying copy-on-write if needed.
    let (loc, origin) = uniquify(path: &expr.lvalue)
    // let (loc, origin) = expr.lvalue.accept(pathVisitor: &self)
    assert(origin == nil, "left operand is prefixed by an rvalue")

    // Drop the current value held by the left operand.
    emit(drop: loc, type: expr.lvalue.type!)

    // Emit the assignment.
    if isMovable(expr.rvalue) {
      emit(move: &expr.rvalue, to: loc)
    } else {
      emit(copy: &expr.rvalue, to: loc)
    }

    // Emit the body of the expression.
    return expr.body.accept(&self)
  }

  public mutating func visit(_ expr: inout ErrorExpr) -> IRValue {
    fatalError()
  }

  public mutating func visit(_ expr: inout NamePath) -> IRValue {
    let loc = bindings[expr.name]!

    if expr.type!.isAddressOnly {
      let alloca = addEntryAlloca(type: lower(expr.type!))
      emit(init: alloca, type: expr.type!)
      emit(copy: loc, type: expr.type!, to: alloca)
      return alloca
    } else {
      return builder.buildLoad(loc, type: lower(expr.type!))
    }
  }

  public mutating func visit(path: inout NamePath) -> PathResult {
    return (loc: bindings[path.name]!, origin: nil)
  }

  public mutating func visit(_ expr: inout ElemPath) -> IRValue {
    // Emit the address of the selected element.
    let (loc, origin) = visit(path: &expr)

    // Emit the element's value.
    let result: IRValue
    if expr.type!.isAddressOnly {
      let alloca = addEntryAlloca(type: lower(expr.type!))
      emit(init: alloca, type: expr.type!)
      emit(copy: loc, type: expr.type!, to: alloca)
      result = alloca
    } else {
      result = builder.buildLoad(loc, type: lower(expr.type!))
    }

    // Drop the path origin if necessary.
    if let (value, type) = origin {
      emit(drop: value, type: type)
    }

    return result
  }

  public mutating func visit(path: inout ElemPath) -> PathResult {
    guard case .array(let elemType) = path.base.type else { unreachable() }
    let elemIRType = lower(elemType)
    let elemIRTypePtr = elemIRType.ptr

    // Emit the base expression.
    let pathBase: IRValue
    let origin  : PathValueOrigin?
    if var path = path.base as? Path {
      (pathBase, origin) = path.accept(pathVisitor: &self)
    } else {
      pathBase = path.base.accept(&self)
      origin = (value: pathBase, type: path.base.type!)
    }

    // Emit the array's address.
    var base = builder.buildStructGEP(pathBase, type: anyArrayType, index: 3)
    base = builder.buildLoad(base, type: voidPtr)
    base = builder.buildBitCast(base, type: elemIRTypePtr)

    // Emit the address of the selected element.
    assert(path.index.type == .int)
    let idx = path.index.accept(&self)
    let loc = builder.buildInBoundsGEP(base, type: elemIRType, indices: [idx])

    return (loc: loc, origin: origin)
  }

  public mutating func visit(_ expr: inout PropPath) -> IRValue {
    // Emit the address of the selected element.
    let (loc, origin) = visit(path: &expr)

    // Emit the selected member.
    let result: IRValue
    if expr.type!.isAddressOnly {
      let alloca = addEntryAlloca(type: lower(expr.type!),  name: expr.name)
      emit(init: alloca, type: expr.type!)
      emit(copy: loc, type: expr.type!, to: alloca)
      result = alloca
    } else {
      result = builder.buildLoad(loc, type: lower(expr.type!))
    }

    // Drop the path origin if necessary.
    if let (value, type) = origin {
      emit(drop: value, type: type)
    }

    return result
  }

  public mutating func visit(path: inout PropPath) -> PathResult {
    // Emit the base expression.
    let pathBase: IRValue
    let origin  : PathValueOrigin?
    if var path = path.base as? Path {
      (pathBase, origin) = path.accept(pathVisitor: &self)
    } else {
      pathBase = path.base.accept(&self)
      origin = (value: pathBase, type: path.base.type!)
    }

    // Emit the address of the selected member.
    guard case .struct(name: _, let props) = path.base.type else { unreachable() }
    let i = props.firstIndex(where: { $0.name == path.name })!
    let loc = builder.buildStructGEP(pathBase, type: lower(path.base.type!), index: i)

    return (loc: loc, origin: origin)
  }

  /// Emits a writeable location, uniquifying the base of the path if necessary.
  ///
  /// This method is intended to be a drop-in replacement of `visit(path:)` in situations where the
  /// returned location must be made unique before it is used for a write access.
  private mutating func uniquify(path: inout Path) -> PathResult {
    switch path {
    case is NamePath:
      return path.accept(pathVisitor: &self)
    case var elemPath as ElemPath:
      return uniquify(elemPath: &elemPath)
    case var propPath as PropPath:
      return uniquify(propPath: &propPath)
    default:
      unreachable()
    }
  }

  private mutating func uniquify(elemPath path: inout ElemPath) -> PathResult {
    // Uniquify the prefix of the base.
    guard var pathBase = path.base as? Path else { fatalError("path is prefixed by an rvalue") }
    let (pathBaseLoc, pathOrigin) = uniquify(path: &pathBase)
    assert(pathOrigin == nil)

    // Uniquify the base array.
    let elemType = path.type!
    let elemMetatype: IRValue = elemType.isTrivial
      ? metatypeType.ptr.null()
      : metatype(of: elemType)
    _ = builder.buildCall(runtime.arrayUniq, args: [pathBaseLoc, elemMetatype])

    let elemIRType = lower(elemType)
    let elemIRTypePtr = elemIRType.ptr

    // Emit the array's address.
    var base = builder.buildStructGEP(pathBaseLoc, type: anyArrayType, index: 3)
    base = builder.buildLoad(base, type: voidPtr)
    base = builder.buildBitCast(base, type: elemIRTypePtr)

    // Emit the address of the selected element.
    assert(path.index.type == .int)
    let idx = path.index.accept(&self)
    let loc = builder.buildInBoundsGEP(base, type: elemIRType, indices: [idx])

    return (loc: loc, origin: nil)
  }

  private mutating func uniquify(propPath path: inout PropPath) -> PathResult {
    guard var pathBase = path.base as? Path else { fatalError("path is prefixed by an rvalue") }
    let (pathBaseLoc, pathOrigin) = uniquify(path: &pathBase)
    assert(pathOrigin == nil)

    // Emit the address of the selected member.
    guard case .struct(name: _, let props) = path.base.type else { unreachable() }
    let i = props.firstIndex(where: { $0.name == path.name })!
    let loc = builder.buildStructGEP(pathBaseLoc, type: lower(path.base.type!), index: i)

    return (loc: loc, origin: nil)
  }

  // ----------------------------------------------------------------------------------------------
  // MARK: Helpers
  // ----------------------------------------------------------------------------------------------

  private func zext(_ value: IRValue) -> IRValue {
    return builder.buildZExt(value, type: IntType.int64)
  }

  /// Returns a Boolean value indicating whether the result of the given expression can be moved.
  ///
  /// If an rvalue has an address-only type, then its value  can be moved in assignments rather
  /// than copied, thus avoiding unnecessary allocations.
  ///
  /// - Parameter expr: An expression.
  private func isMovable(_ expr: Expr) -> Bool {
    return expr.type!.isAddressOnly
  }

  /// Lowers the given semantic type to LLVM.
  ///
  /// - Parameter type: A MVS semantic type to lower.
  private func lower(_ type: Type) -> IRType {
    switch type {
    case .int:
      return IntType.int64
    case .float:
      return FloatType.double
    case .struct(let name, _):
      return module.type(named: name)!
    case .array:
      return anyArrayType
    case .inout(let base):
      return lower(base).ptr
    case .func:
      return anyClosureType
    case .error:
      fatalError("cannot lower type the error type to LLVM")
    }
  }

  /// Returns a pointer to the metatype of the given type.
  ///
  /// - Parameter type: The MVS semantic type whose metatype should be emitted.
  private func metatype(of type: Type) -> IRValue {
    switch type {
    case .struct(let name, _):
      return metatypes[name]!

    case .array(let elemType):
      return emit(metatypeForArrayOf: elemType)

    default:
      return metatypeType.ptr.null()
    }
  }

  /// Builds a lowered function type with the given parameter and output types.
  ///
  /// - Parameters:
  ///   - params: An array with the MVS semantic type of each formal parameter.
  ///   - output: The MVS semantic type of the return value.
  private func buildFunctionType(from params: [Type], to output: Type) -> FunctionType {
    var irParamTypes: [IRType] = []
    irParamTypes.reserveCapacity(params.count)

    // Lower the function's formal parameters.
    for type in params {
      if case .inout(let base) = type {
        // Inout types are always passed by address.
        irParamTypes.append(lower(base).ptr)
      } else if type.isAddressOnly {
        // Address-only types are passed by address.
        irParamTypes.append(lower(type).ptr)
      } else {
        // Other types are passed directly.
        irParamTypes.append(lower(type))
      }
    }

    // The environment is passed as an arbitrary pointer, at the end of the parameter list.
    irParamTypes.append(PointerType.toVoid)

    // If the output has an address-only type, we pass it as first parameter.
    if output.isAddressOnly {
      irParamTypes.insert(lower(output).ptr, at: 0)
      return FunctionType(irParamTypes, VoidType())
    } else {
      return FunctionType(irParamTypes, lower(output))
    }
  }

  /// Returns the offset in bytes between successive objects of the specified type, including
  /// alignment padding.
  ///
  /// - Parameter type: The LLVM type whose stride should be returned.
  private func stride(of type: IRType) -> IRValue {
    return i64(Int(target.dataLayout.allocationSize(of: type)))
  }

  /// Creates an alloca at the beginning of the current function.
  ///
  /// - Parameters:
  ///   - type: The sized type used to determine the amount of stack memory to allocate.
  ///   - count: An optional number of elements to allocate.
  ///   - name: The name for the newly inserted instruction.
  private func addEntryAlloca(
    type: IRType, count: IRValue? = nil, name: String = ""
  ) -> IRInstruction {
    // Save the current insertion pointer.
    let oldInsertBlock = builder.insertBlock

    // Move to the function's entry.
    let entry = builder.currentFunction!.entryBlock!
    if let loc = entry.instructions.first(where: { !$0.isAAllocaInst }) {
      builder.positionBefore(loc)
    } else {
      builder.positionAtEnd(of: entry)
    }

    // Build the alloca.
    let alloca = builder.buildAlloca(type: type, count: count, name: name)

    // Restore the insertion pointer.
    oldInsertBlock.map(builder.positionAtEnd(of:))
    return alloca
  }

  /// Returns a constant of type `i64`.
  private func i64(_ value: Int) -> IRValue {
    IntType.int64.constant(value)
  }

}
