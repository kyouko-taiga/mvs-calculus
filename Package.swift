// swift-tools-version:5.3
import PackageDescription

let package = Package(
  name: "mvs",
  platforms: [
    .macOS(.v11)
  ],
  products: [
    .executable(name: "mvs", targets: ["Driver"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "0.4.0"),
    .package(url: "https://github.com/kyouko-taiga/Diesel.git", from: "1.1.0"),
    .package(name: "LLVM", url: "https://github.com/llvm-swift/LLVMSwift.git", .branch("master")),
  ],
  targets: [
    .target(
      name: "Driver",
      dependencies: [
        "AST", "CodeGen", "Parse", "Sema",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),

    .target(name: "AST", dependencies: ["Basic"]),
    .target(name: "Basic"),
    .target(name: "CodeGen", dependencies: ["AST", "Basic", "LLVM"]),
    .target(name: "Parse", dependencies: ["AST", "Basic", "Diesel"]),
    .target(name: "Sema", dependencies: ["AST", "Basic"]),

    .testTarget(name: "MVSTests")
  ])
