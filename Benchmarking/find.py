import multiprocessing as mp
import subprocess as subp
import generator
import shutil as sh
import hashlib

from gen import ROOT_DIR

FAIL_DIR = os.path.join(ROOT_DIR, 'fail')


def hash(s):
  h = hashlib.new('sha256')
  h.update(s)
  return h.hexdigest()


def main(i: int):
  while True:
    try:
      gen.main(f'gen{i}')
      try:
        subp.run(['.build/release/mvs', f'gen{i}.mvs'],
                 stderr=subp.PIPE, stdout=subp.PIPE, check=True)
      except Exception as e:
        print(f'- recording a failure: {e}')
        h = hash(open(f'gen{i}.mvs').read().encode('utf-8'))
        sh.copyfile(f'gen{i}.mvs', f'{FAIL_DIR}/{h}.mvs')
    except:
      print('- generator crash')


if __name__ == "__main__":
  for i in range(12):
    p = mp.Process(target=main, args=(i,))
    p.start()
