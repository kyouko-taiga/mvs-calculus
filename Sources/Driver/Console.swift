import Foundation

import AST
import Basic

struct Console: DiagnosticConsumer {

  /// The source input of the lexer.
  let source: String

  func consume(_ diagnostic: Diagnostic) {
    guard let range = diagnostic.range else {
      // Print the diagnostic without any source location.
      error("\(diagnostic.level): \(diagnostic.message)\n")
      return
    }

    let start = range.lowerBound < source.endIndex
      ? range.lowerBound
      : source.lastIndex(where: { _ in true })

    // Print the location at which the diagnostic occured.
    if let location = start {
      let indices = lineColumnIndices(at: location)
      error("\(indices.line):\(indices.column): ")
    }

    // Print the diagnostic.
    error("\(diagnostic.level): \(diagnostic.message)\n")

    // Highlight the diagnostic range.
    if let location = start {
      let excerpt = line(containing: location)
      error(excerpt)
      error("\n")

      let padding = source.distance(from: excerpt.startIndex, to: location)
      let count = source.distance(from: location, to: min(range.upperBound, excerpt.endIndex))

      error(String(repeating: " ", count: padding))
      if count > 1 {
        error(String(repeating: "~", count: count))
      } else {
        error("^")
      }
      error("\n")
    }
  }

  /// Returns the line containing the given location.
  ///
  /// - Parameter location: A location within this source inout.
  public func line(containing location: SourceRange.Bound) -> Substring {
    var lower = location
    while lower > source.startIndex {
      let predecessor = source.index(before: lower)
      if source[predecessor].isNewline {
        break
      } else {
        lower = predecessor
      }
    }

    var upper = location
    while upper < source.endIndex && !source[upper].isNewline {
      upper = source.index(after: upper)
    }

    return source[lower ..< upper]
  }

  /// Returns the 1-based line and column indices of the given location.
  ///
  /// - Parameter location: A location within this source file.
  public func lineColumnIndices(at location: String.Index) -> (line: Int, column: Int) {
    var lineIndex = 1
    for c in source[...location] where c.isNewline {
      lineIndex += 1
    }

    let contents = source.prefix(through: location)
    var columnIndex = 0
    for c in contents.reversed() {
      guard !c.isNewline else { break }
      columnIndex += 1
    }

    return (lineIndex, columnIndex)
  }

  /// Writes the given message to the standard error.
  ///
  /// - Parameter string: A message.
  func error<S>(_ string: S) where S: StringProtocol {
    FileHandle.standardError.write(string.data(using: .utf8)!)
  }

}
