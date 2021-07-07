import generator
import hashlib
import multiprocessing as mp
import os
import shutil as sh
import subprocess as subp
import sys

from generator import ROOT_DIR, SRC_DIR

FAIL_DIR = os.path.join(ROOT_DIR, 'fail')


def hash(s):
  h = hashlib.new('sha256')
  h.update(s)
  return h.hexdigest()


def main(i: int):
  while True:
    try:
      generator.main(f'gen{i}')
    except:
      print('- generator crash')
      continue

    try:
      subp.run(
        ['.build/release/mvs', f'{SRC_DIR}/gen{i}.mvs', '-o', '/dev/null'],
        stderr=subp.PIPE, stdout=subp.PIPE, check=True)
    except Exception as e:
      print(f'- recording a failure: {e}')
      h = hash(open(f'gen{i}.mvs').read().encode('utf-8'))
      sh.copyfile(f'gen{i}.mvs', f'{FAIL_DIR}/{h}.mvs')


if __name__ == '__main__':
  n = int(sys.argv[1]) if len(sys.argv) > 1 else 1
  for i in range(n):
    p = mp.Process(target=main, args=(i,))
    p.start()
