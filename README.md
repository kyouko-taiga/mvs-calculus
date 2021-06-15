# MVS-Calculus

This is a proof of concept compiler for the *mvs-calculus*.

## Benchmarking

Compile for benchmark:

```bash
mvs input.mvs --benchmark 100 2> main.ll
c++ -c -std=c++14 clock.cc
cc  -c runtime.c
c++ runtime.o clock.o main.ll -o main
```
