import os
import subprocess as subp
import gen
import shutil as sh
import numpy as np
import json
import itertools
import pathlib

from gen import ROOT_DIR, SRC_DIR

RUN_COUNT = 20
OUT_DIR = os.path.join(ROOT_DIR, 'out')


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
    subp.run(['swiftc', f'{SRC_DIR}/gen.swift', '-o', f'{OUT_DIR}/gen.swift.out'],
             stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    return collect_runs_p50(f'./{OUT_DIR}/gen.swift.out')

  def bench_cpp():
    print('-- cpp')
    subp.run(['clang++', '-std=c++14', '-O2', f'{SRC_DIR}/gen.cpp', '-o', f'{OUT_DIR}/gen.cpp.out'],
             stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    return collect_runs_p50(f'./{OUT_DIR}/gen.cpp.out')

  def bench_mvs():
    print('-- mvs')
    compiled = subp.run(['.build/release/mvs',
                         '--benchmark', '1000', '-O', '--emit-llvm',
                         f'{SRC_DIR}/gen.mvs'],
                        stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    with open(f'{OUT_DIR}/gen.mvs.ll', 'wb') as f:
      f.write(compiled.stderr)
    subp.run(['clang++', '-std=c++14', '-O2',
              f'{OUT_DIR}/gen.mvs.ll', 'Runtime/runtime.cc',
              '-o', f'{OUT_DIR}/gen.mvs.out'],
             stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    return collect_runs_p50(f'./{OUT_DIR}/gen.mvs.out')

  def bench_scala():
    print('-- scala')
    mkdir(f'{SRC_DIR}/main/scala')
    sh.move(f'{SRC_DIR}/gen.scala', f'{SRC_DIR}/main/scala/gen.scala')
    subp.run(['sbt', 'nativeLink'], cwd=f'{ROOT_DIR}/')
    return collect_runs_p50(f'./{ROOT_DIR}/target/scala-2.12/gen-out')

  if not os.path.exists(OUT_DIR):
    os.makedirs(OUT_DIR)

  with open(f'{ROOT_DIR}/results.csv', 'w') as f:
    f.write('cpp,swift,mvs,scala\n')
    for i in itertools.count(start=1):
      print(f'--- bench {i}')
      try:
        gen.main(f'gen')
        try:
          swift_result = bench_swift()
          cpp_result = bench_cpp()
          mvs_result = bench_mvs()
          scala_result = bench_scala()
          f.write(f'{cpp_result},{swift_result},{mvs_result},{scala_result}\n')
          f.flush()
        except Exception as e:
          print(f'- bench failure: {e}')
      except Exception as e:
        print(f'- generator failure: {e}')


if __name__ == '__main__':
  main()
