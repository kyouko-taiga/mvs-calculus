/// Marks this code path as unreachable
public func unreachable(file: StaticString = #file, line: UInt = #line) -> Never {
  fatalError()
}
