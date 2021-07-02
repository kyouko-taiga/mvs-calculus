import subprocess as subp
import gen
import shutil as sh
import numpy as np
import json
import itertools

RUN_COUNT = 20


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
    subp.run(['swiftc', 'gen.swift', '-o', 'gen.swift.out'],
             stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    return collect_runs_p50('./gen.swift.out')

  def bench_cpp():
    print('-- cpp')
    subp.run(['clang++', '-O2', 'gen.cpp', '-o', 'gen.cpp.out'],
             stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    return collect_runs_p50('./gen.cpp.out')

  def bench_mvs():
    print('-- mvs')
    compiled = subp.run(['.build/release/mvs',
                         '--benchmark', '1000', 'gen.mvs'],
                        stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    with open("gen.mvs.ll", 'wb') as f:
      f.write(compiled.stderr)
    subp.run(['clang', '-S', '-emit-llvm',
              'Runtime/runtime.c', '-o', 'Runtime/runtime.ll'],
             stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    subp.run(['clang++', '-O2',
              'gen.mvs.ll',
              'Runtime/runtime.ll',
              'Runtime/clock.cc',
              '-o', 'gen.mvs.out'],
             stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    return collect_runs_p50('./gen.mvs.out')

  with open('results.csv', 'w') as f:
    f.write('cpp,swift,mvs\n')
    for i in itertools.count(start=1):
      print(f"--- bench {i}")
      try:
        gen.main(f'gen')
        try:
          swift_result = bench_swift()
          cpp_result = bench_cpp()
          mvs_result = bench_mvs()
          f.write(f"{cpp_result},{swift_result},{mvs_result}\n")
          f.flush()
        except Exception as e:
          print(f'- bench failure: {e}')
      except Exception as e:
        print(f'- generator failure: {e}')


if __name__ == "__main__":
  main()
