import Foundation
import ArgumentParser

import AST
import CodeGen
import Parse
import Sema

struct MVS: ParsableCommand {

  @Argument(help: "The source program.", transform: URL.init(fileURLWithPath:))
  var inputFile: URL

  func run() throws {
    let input = try String(contentsOf: inputFile)

    // Create an AST context.
    let console = Console(source: input)
    var context = Context()
    context.diagConsumer = console

    var parser = MVSParser()
    guard var program = parser.parse(source: input, diagConsumer: console) else {
      return
    }

    // Type check the program.
    let isWellTyped = context.withUnsafeMutablePointer({ (ctx) -> Bool in
      var checker = TypeChecker(context: ctx)
      return checker.visit(&program)
    })
    guard isWellTyped else { return }

    var emitter = try Emitter()
    let module = try emitter.emit(program: &program)
    module.dump()
  }

}

MVS.main()
