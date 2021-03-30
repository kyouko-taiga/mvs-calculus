import Foundation
import ArgumentParser

import AST
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

    var parser = MVSParser(source: input)
    guard var program = parser.parse(source: input, consumer: console) else {
      return
    }

    // Type check the program.
    context.withUnsafeMutablePointer({ ctx in
      var checker = TypeChecker(context: ctx)
      print(checker.visit(&program))
    })
  }


}

MVS.main()
