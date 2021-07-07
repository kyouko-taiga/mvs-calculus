import Foundation
import ArgumentParser

import AST
import CodeGen
import Parse
import Sema

struct MVS: ParsableCommand {

  @Argument(help: "The source program.", transform: URL.init(fileURLWithPath:))
  var inputFile: URL

  @Option(help: "Wrap the program inside a benchmark.")
  var benchmark: Int?

  @Option(help: "The maximum size for stack-allocated arrays.")
  var maxStackArraySize: Int = 256

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

    var emitter = try Emitter(
      mode              : mode,
      shouldEmitPrint   : !noPrint,
      maxStackArraySize : maxStackArraySize)
    let module = try emitter.emit(program: &program)
    module.dump()
  }

}

MVS.main()
