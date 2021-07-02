import subprocess as subp
import glob


def main():
  files = list(glob.glob("fail/*.mvs"))
  successes = 0
  failures = 0

  print("rerunning previous failures")

  def status():
    print(f"failing: {failures}, ok: {successes}, total: {len(files)}")
  
  for f in files:
    try:
      subp.run(['.build/release/mvs', f],
               stderr=subp.PIPE, stdout=subp.PIPE, check=True)
      successes += 1
    except Exception as e:
      failures += 1
    status()


if __name__ == "__main__":
  main()
