import Foundation
import ArgumentParser
import LLVM

import AST
import CodeGen
import Parse
import Sema

struct MVS: ParsableCommand {

  @Argument(help: "The source program.", transform: URL.init(fileURLWithPath:))
  var inputFile: URL

  @Option(name: .short, help: "The output file.", transform: URL.init(fileURLWithPath:))
  var outputFile: URL?

  @Option(help: "Wrap the program inside a benchmark.")
  var benchmark: Int?

  @Option(help: "Set the maximum size for stack-allocated arrays.")
  var maxStackArraySize: Int = 256

  @Flag(help: "Dump the LLVM representation of the program.")
  var emitLLVM: Bool = false

  @Flag(name: [.customShort("O")], help: "Compile with optimizations.")
  var optimize: Bool = false

  @Flag(help: "Disable the printing of the program's value.")
  var noPrint: Bool = false

  func run() throws {
    let input = try String(contentsOf: inputFile)

    // Create a diagnostic consumer.
    let console = Console(source: input)

    // Parse the program.
    var parser = MVSParser()
    guard var program = parser.parse(source: input, diagConsumer: console) else { return }

    // Type check the program.
    var checker = TypeChecker(diagConsumer: console)
    guard checker.visit(&program) else { return }

    // Emit the program's IR.
    let mode: EmitterMode
    if let n = benchmark {
      precondition(n > 0, "number of runs should be greater than 0")
      mode = .benchmark(count: n)
    } else if optimize {
      mode = .release
    } else {
      mode = .debug
    }

    let target = try TargetMachine()
    var emitter = try Emitter(
      target            : target,
      mode              : mode,
      shouldEmitPrint   : !noPrint,
      maxStackArraySize : maxStackArraySize)
    let module = try emitter.emit(program: &program)

    if emitLLVM {
      module.dump()
    } else {
      let output = outputFile ?? inputFile.deletingPathExtension().appendingPathExtension("o")
      try target.emitToFile(module: module, type: .object, path: output.path)
    }
  }

}

MVS.main()
