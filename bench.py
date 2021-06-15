import subprocess as subp
import gen
import shutil as sh
import hashlib


def hash(s):
  h = hashlib.new('sha256')
  h.update(s)
  return h.hexdigest()


def main():
  swift_results = []
  mvs_results = []

  def bench_swift():
    subp.run(['swiftc', 'gen.swift'],
             stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    result = subp.run(['./gen'],
                      stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    print(result.stdout)
    lines = list(filter(lambda x: x, 
                        result.stdout.decode('utf-8').split('\n')))
    return float(lines[-1])

  def bench_mvs():
    compiled = subp.run(['.build/release/mvs', f'gen.mvs'],
                        stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    with open("gen.mvs.ll", 'wb') as f:
      f.write(compiled.stderr)
    subp.run(['clang', 'gen.mvs.ll', 'Runtime/runtime.c', '-o', 'gen.mvs.out'],
             stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    result = subp.run(['./gen.mvs.out'],
                      stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    print(result.stdout)
    return 0

  for i in range(10):
    print(f"--- bench {i}")
    try:
      gen.main(f'gen')
      try:
        swift_result = bench_swift()
        mvs_result = bench_mvs()
        swift_results.append(swift_result)
        mvs_results.append(mvs_result)
      except Exception as e:
        print(f'- bench failure: {e}')
    except Exception as e:
      print(f'- generator failure: {e}')



if __name__ == "__main__":
  main()
