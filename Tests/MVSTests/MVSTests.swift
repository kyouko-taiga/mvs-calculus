import XCTest
import LLVM

import AST
import CodeGen
import Parse
import Sema

final class MVSTests: XCTestCase {

  /// A file manager.
  private let manager = FileManager.default

  func testCompiler() throws {
    let urls = try XCTUnwrap(
      Bundle.module.urls(forResourcesWithExtension: "mvs", subdirectory: "TestCases"),
      "No test case found")

    for url in urls {
      let result = try XCTContext.runActivity(named: url.lastPathComponent, block: { _ -> Bool in
        // Read the input file.
        guard let input = try? String(contentsOf: url) else {
          XCTFail("Failed to open '\(url)'")
          return false
        }

        // Create a diagnostic consumer.
        let consumer = Consumer()

        // Parse the program.
        var parser = MVSParser()
        guard var program = parser.parse(source: input, diagConsumer: consumer) else {
          return false
        }

        // Type check the program.
        var checker = TypeChecker(diagConsumer: consumer)
        guard checker.visit(&program) else {
          return false
        }

        // Extract the expected output.
        guard let range = input.range(of: "#!output") else { return false }
        let expected = input[range.upperBound...]
          .drop  (while: { $0.isWhitespace })
          .prefix(while: { !$0.isNewline })

        // Emit the program's IR.
        var emitter = try Emitter(shouldEmitPrint: true)
        let module = try emitter.emit(program: &program)

        let output = try exec(module: module, on: emitter.target) ?? ""
        return output == expected
      })

      if result {
        print("    - \(url.lastPathComponent): passed")
      } else {
        XCTFail("\(url.lastPathComponent)")
      }
    }
  }

  /// Compiles and executes the given module.
  ///
  /// - Parameters:
  ///   - module: The LLVM module to compile and execute.
  ///   - target: The target machine for which the module should be compiled.
  private func exec(module: LLVM.Module, on target: TargetMachine) throws -> String? {
    // Compile the module.
    let temporary = try manager.url(
      for           : .itemReplacementDirectory,
      in            : .userDomainMask,
      appropriateFor: productsDirectory,
      create        : true)
    let object = temporary.appendingPathComponent("\(module.name).o")
    try target.emitToFile(module: module, type: .object, path: object.path)

    // Get the path to the runtime library.
    let runtime = ProcessInfo.processInfo.environment["MVS_RUNTIME"]
      ?? productsDirectory.appendingPathComponent("runtime.c").path

    // Link the module.
    let output = temporary.appendingPathComponent("\(module.name)")
    _ = try exec("/usr/bin/clang", args: [object.path, runtime, "-lm", "-o", output.path])

    // Run the executable.
    return try exec(output.path)
  }

  /// Executes the given executable.
  ///
  /// - Parameters:
  ///   - path: The path to the executable that should be ran.
  ///   - args: A list of arguments that are passed to the executable.
  ///
  /// - Returns: The standard output of the process, or `nil` if it was empty.
  private func exec(_ path: String, args: [String] = []) throws -> String? {
    let pipe = Pipe()
    let process = Process()

    process.executableURL = URL(fileURLWithPath: path).absoluteURL
    process.arguments = args
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()

    guard let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8)
    else {
      return nil
    }

    let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : result
  }


  /// The path to the built products directory.
  var productsDirectory: URL {
    #if os(macOS)
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
      return bundle.bundleURL.deletingLastPathComponent()
    }
    fatalError("couldn't find the products directory")
    #else
    return Bundle.main.bundleURL
    #endif
  }

}

private struct Consumer: DiagnosticConsumer {

  /// The line number at which assertion failures are thrown.
  var line: UInt

  init(line: UInt = #line) {
    self.line = line
  }

  func consume(_ diagnostic: Diagnostic) {
    XCTFail("unexpected diagnostic: \(diagnostic.message)", file: #file, line: line)
  }
  
}
