# MVS-Calculus

The *mvs-calculus* is a small experimental language, centered around the concept of *mutable value semantics*.

Unrestricted mutation of shared state is a source of many well-known problems.
The predominant safe solutions are pure functional programming, which simply bans mutation.
Mutable value semantics is a different approach that bans sharing instead of mutation, thereby supporting part-wise in-place mutationand local reasoning.

## Installation

This project is written in [Swift](https://swift.org) and distributed in the form of a package, built with [Swift Package Manager](https://swift.org/package-manager/).

You will need to install LLVM 11.0.
Use your favorite package manager (e.g., `port` on macOS or `apt` on Ubuntu) and make sure `llvm-config` is in your PATH.
Then, create a `pkgconfig` file for your specific installation
The maintainers of [LLVMSwift](https://github.com/llvm-swift/LLVMSwift) were kind enough to provide a script:

```bash
swift package resolve
swift .build/checkouts/LLVMSwift/utils/make-pkgconfig.swift
```

> On Ubuntu, you will also need [libc++](https://libcxx.llvm.org) to link your code with LLVM:
>
> ```bash
> apt-get install libc++-dev
> apt-get install libc++abi-dev
> ```

Once LLVM is installed and configure, compile the compiler and the runtime library with the following commands:

```bash
swift build -c release
c++ -std=c++14 -c Runtime/runtime.cc -o .build/release/runtime.o
```

> You may compile the runtime with the flag `DEBUG` for debugging purposes.
> Calls the the runtime's API will be logged as program are executed.

## Usage

The `mvs` executable compiles programs into object files, which you can link with `clang` or `ld`.
Pass the flag `-O` to compile with optimizations.

```bash
.build/release/mvs -O Examples/Factorial.mvs
c++ .build/release/runtime.o Examples/Factorial.o -o Examples/Factorial
Examples/Factorial
# Prints 720
```

Run `mvs --help` for an overview of the compiler's options.
