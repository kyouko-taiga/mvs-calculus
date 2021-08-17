import sys

def normalize(input_file):
  output_file = input_file + ".normalized"

  with open(input_file) as f_in:
    with open(output_file, 'w') as f_out:
      lines = list(f_in.readlines())
      f_out.write("bench-name,cpp-time,mvs-time,swift-time,scala-time\n")
      for line in lines[1:]:
        name, *rest = line.split(",")
        t1, m1, t2, m2, t3, m3, t4, m4 = map(float, rest)
        min_t = min(t for t in [t1, t2, t3, t4] if t > 0)
        nt = lambda t: t/min_t
        f_out.write(f"{name},{nt(t1)},{nt(t2)},{nt(t3)},{nt(t4)}\n")

if __name__ == "__main__":
  input_file = sys.argv[1]
