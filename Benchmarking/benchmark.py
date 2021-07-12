import itertools
import numpy as np
import os
import pathlib
import shutil as sh
import subprocess as subp

from .generator import gen
from .generator.gen import ROOT_DIR, SRC_DIR

RUN_COUNT = 20
OUT_DIR = os.path.join(ROOT_DIR, 'out')


def collect_runs_p50(binary):
  exec_time = []
  memo_cons = []

  for x in range(RUN_COUNT):
    # Run the binary.
    result = subp.run([binary], stderr=subp.PIPE, stdout=subp.PIPE, check=True)

    # Parse the binary's output.
    lines = list(filter(lambda x: x, result.stdout.decode('utf-8').split('\n')))
    value = float(lines[0])
    xtime = float(lines[-1])
    print(f'  {value:.5g} {xtime / 1_000_000:.2f}ms')

    # Store results.
    exec_time.append(xtime)
    memo_cons.append(0)#float(result.stderr.splitlines()[1].split()[0]))  # Max resident set size

  print()

  # Return the median of measured execution times and memory consumption.
  x = np.percentile(exec_time, 50)
  y = np.percentile(memo_cons, 50)
  return (x, y)


def bench_cpp(process_kwargs):
  print('## cpp')
  process_kwargs['timeout'] = 300
  subp.run(
    ['clang++', '-std=c++14', '-O2', f'{SRC_DIR}/gen.cpp', '-o', f'{OUT_DIR}/gen.cpp.out'],
    **process_kwargs)
  return collect_runs_p50(f'./{OUT_DIR}/gen.cpp.out')


def bench_mvs(process_kwargs):
  print('## mvs')
  subp.run(
    [
      '.build/release/mvs', f'{SRC_DIR}/gen.mvs',
     '-o', f'{OUT_DIR}/gen.mvs.o'
    ],
    **process_kwargs)
  subp.run(
    [
      'clang++', '-std=c++14', f'{OUT_DIR}/gen.mvs.o', 'Runtime/runtime.cc',
      '-o', f'{OUT_DIR}/gen.mvs.out'
    ],
    **process_kwargs)
  return collect_runs_p50(f'./{OUT_DIR}/gen.mvs.out')


def bench_swift(process_kwargs):
  print('## swift')
  subp.run(
    ['swiftc', '-Ounchecked', f'{SRC_DIR}/gen.swift', '-o', f'{OUT_DIR}/gen.swift.out'],
    **process_kwargs)
  return collect_runs_p50(f'./{OUT_DIR}/gen.swift.out')


def bench_scala(process_kwargs):
  print('## scala')
  os.makedirs(f'{SRC_DIR}/main/scala', exist_ok=True)
  sh.move(f'{SRC_DIR}/gen.scala', f'{SRC_DIR}/main/scala/gen.scala')
  subp.run(
    ['sbt', 'nativeLink'], cwd=f'{ROOT_DIR}/',
    **process_kwargs)
  return collect_runs_p50(f'./{ROOT_DIR}/target/scala-2.12/gen-out')


def main(verbose=False):
  # Create the output directory.
  if not os.path.exists(OUT_DIR):
    os.makedirs(OUT_DIR)

  # Create a report file.
  i = 1
  report_filename = os.path.join(ROOT_DIR, 'results.csv')
  while os.path.exists(report_filename):
    report_filename = os.path.join(ROOT_DIR, f'results.{i}.csv')
    i = i + 1

  process_kwargs = dict(stderr=subp.PIPE, stdout=subp.PIPE, check=True) if not verbose else {}

  # Run the benchmarks.
  with open(report_filename, 'w') as f:
    f.write('cpp-time,cpp-memo,')
    f.write('mvs-time,mvs-memo,')
    f.write('swift-time,swift-memo,')
    f.write('scala-time,scala-memo\n')
    f.flush()

    for i in itertools.count(start=1):
      print(f'# Benchmark {i}')

      # Generate a program.
      try:
        gen.main(f'gen')
      except Exception as e:
        print(f'Generator failed: {e}\n')
        continue

      # Compile and measure performances.
      try:
        (cpp_time, cpp_memo) = bench_cpp(process_kwargs)
        (mvs_time, mvs_memo) = bench_mvs(process_kwargs)
        (swf_time, swf_memo) = bench_swift(process_kwargs)
        (scl_time, scl_memo) = bench_scala(process_kwargs)

        f.write(f'{cpp_time},{cpp_memo},')
        f.write(f'{mvs_time},{mvs_memo},')
        f.write(f'{swf_time},{swf_memo},')
        f.write(f'{scl_time},{scl_memo}\n')
        f.flush()
      except Exception as e:
        print(f'Benchmark failed: {e}\n')


if __name__ == '__main__':
  main()
