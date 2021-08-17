import sys
import json
from collections import defaultdict
import numpy as np
import matplotlib.pyplot as plt

input_file = sys.argv[1]

names = set()
meta = {}
results = defaultdict(lambda: {})

with open(input_file) as f_in:
  lines = list(f_in.readlines())
  for line in lines[1:]:
    name, *rest = line.split(",")
    t1, m1, t2, m2, t3, m3, t4, m4 = map(float, rest)
    min_t = min(t for t in [t1, t2, t3, t4] if t > 0)
    results[1][name] = t1/min_t
    results[2][name] = t2/min_t
    results[3][name] = t3/min_t
    results[4][name] = t4/min_t
    names.add(name)

for name in names:
  with open(f"Benchmarking/src/{name}.json") as f:
    meta[name] = json.load(f)
    write_count = (meta[name]["op_count"].get("ArraySetInst", 0) +
                   meta[name]["op_count"].get("StructSetInst", 0) +
                   meta[name]["op_count"].get("NewStructInst", 0) +
                   meta[name]["op_count"].get("NewArrayInst", 0) +
                   meta[name]["op_count"].get("VarInst", 0) +
                   meta[name]["op_count"].get("AssignInst", 0))
    meta[name]["write_ratio"] = float(write_count) / meta[name]["total_count"]
    read_count = (meta[name]["op_count"].get("ArrayGetInst", 0) +
                  meta[name]["op_count"].get("StructGetInst", 0))
    meta[name]["read_ratio"] = float(read_count) / meta[name]["total_count"]
    meta[name]["read_write_ratio"] = float(write_count) / float(read_count + write_count) if read_count + write_count > 0 else -1

cpp = 1
mvs = 2
swift = 3
scala = 4

def make_scatter(ratio):
  plt.figure()
  pairs = [
      (scala, 'yellow'),
      (swift, 'blue'),
      (mvs, 'green'),
      (cpp, 'red'),
  ]
  for i, color in pairs:
    x = []
    y = []

    for name, v in results[i].items():
      x.append(meta[name][ratio])
      y.append(v)

    plt.plot(x, y, '.', color=color)

  plt.yscale('log')
  plt.savefig(f"scatter-{ratio}.pdf", dpi=100)


def make_line(ratio, bucket_count, min_x, max_x):
  plt.figure() 

  buckets = range(0, bucket_count)
  d_x = max_x - min_x

  pairs = [
      (scala, 'yellow', 'Scala'),
      (swift, 'blue', 'Swift'),
      (mvs, 'green', 'MVS'),
      (cpp, 'red', 'C++'),
  ]

  for i, color, label in pairs:
    for p in [50]:
      xs = []
      ys = []
      for bucket in buckets:
        x = min_x + d_x * (float(bucket) / bucket_count)
        x2 = min_x + d_x * (float(bucket + 1) / bucket_count)
        values = []
        for name, v in results[i].items():
          r = meta[name][ratio]
          if r >= x and r < x2:
            values.append(v)
        ys.append(np.percentile(values, p) if len(values) > 0 else 0)
        xs.append(x)
      style = '-' if p == 50 else '--'
      plt.plot(xs, ys, style, color=color, label=label)

  plt.yscale('log')
  plt.legend()
  plt.savefig(f"line-{ratio}.pdf", dpi=100)

make_scatter(f'read_ratio')
make_scatter(f'write_ratio')
make_scatter(f'read_write_ratio')
make_line(f'read_ratio', 20, 0.0, 0.8)
make_line(f'write_ratio', 20, 0.1, 0.8)
make_line(f'read_write_ratio', 20, 0.1, 1.0)
