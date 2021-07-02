import os
import subprocess as subp
import gen
import shutil as sh
import numpy as np
import json
import itertools
import pathlib

RUN_COUNT = 20


def mkdir(path):
  pathlib.Path(path).mkdir(parents=True, exist_ok=True)


def main():

  def collect_runs_p50(binary):
    results = []

    for x in range(RUN_COUNT):
      result = subp.run([binary],
                        stderr=subp.PIPE, stdout=subp.PIPE, check=True)
      print(result.stdout)
      lines = list(filter(lambda x: x,
                          result.stdout.decode('utf-8').split('\n')))
      results.append(float(lines[-1]))

    return np.percentile(results, 50)

  def bench_swift():
    print('-- swift')
    subp.run(['swiftc', 'output/gen.swift', '-o', 'output/gen.swift.out'],
             stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    return collect_runs_p50('./output/gen.swift.out')

  def bench_cpp():
    print('-- cpp')
    subp.run(['clang++', '-O2', 'output/gen.cpp', '-o', 'output/gen.cpp.out'],
             stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    return collect_runs_p50('./output/gen.cpp.out')

  def bench_mvs():
    print('-- mvs')
    compiled = subp.run(['.build/release/mvs',
                         '--benchmark', '1000', 'output/gen.mvs'],
                        stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    with open("output/gen.mvs.ll", 'wb') as f:
      f.write(compiled.stderr)
    subp.run(['clang', '-S', '-emit-llvm',
              'Runtime/runtime.c', '-o', 'output/runtime.ll'],
             stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    subp.run(['clang++', '-O2',
              'output/gen.mvs.ll',
              'output/runtime.ll',
              'Runtime/clock.cc',
              '-o', 'output/gen.mvs.out'],
             stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    return collect_runs_p50('./output/gen.mvs.out')

  def bench_scala():
    print('-- scala')
    mkdir('output/src/main/scala')
    sh.move('output/gen.scala', 'output/src/main/scala/gen.scala')
    subp.run(['sbt', 'nativeLink'], cwd='output/')
    return collect_runs_p50('./output/target/scala-2.12/gen-out')

  if not os.path.exists("output"):
    os.mkdir("output")
  with open('output/results.csv', 'w') as f:
    f.write('cpp,swift,mvs,scala\n')
    for i in itertools.count(start=1):
      print(f"--- bench {i}")
      try:
        gen.main(f'gen')
        try:
          swift_result = bench_swift()
          cpp_result = bench_cpp()
          mvs_result = bench_mvs()
          scala_result = bench_scala()
          f.write(f"{cpp_result},{swift_result},{mvs_result},{scala_result}\n")
          f.flush()
        except Exception as e:
          print(f'- bench failure: {e}')
      except Exception as e:
        print(f'- generator failure: {e}')


if __name__ == "__main__":
  main()
