import matplotlib.pyplot as plt
import numpy as np
import os
import pandas
import sys

from generator import ROOT_DIR
from scipy import stats

input = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT_DIR, 'results.csv')
data  = pandas.read_csv(input)

exec_time = data.drop(['cpp-memo', 'mvs-memo', 'swift-memo', 'scala-memo'], axis=1)
exec_time = exec_time.div(1000000)
memo_cons = data.drop(['cpp-time', 'mvs-time', 'swift-time', 'scala-time'], axis=1)
memo_cons = memo_cons.div(1000000)

# Remove outliers.
indices = []
for _ in range(0, 2):
  scores = stats.zscore(exec_time)
  scores = np.abs(scores)
  indices = (scores < 1).all(axis=1)
  exec_time = exec_time[indices]
  memo_cons = memo_cons[indices]

args = dict(patch_artist=True, boxprops=dict(facecolor='#ffe5cc'))

fig, axs = plt.subplots(2, 1)

axs[0].boxplot(exec_time, vert=False, widths=0.75, **args)
axs[0].set_title('Execution time (ms)', fontsize=14)
axs[0].set_yticklabels(['c++', 'mvs', 'Swift', 'Scala'], fontsize=14)
plt.setp(axs[0].get_xticklabels(), fontsize=14)

axs[1].boxplot(memo_cons, vert=False, widths=0.75, **args)
axs[1].set_title('Memory consumption (MB)', fontsize=14)
axs[1].set_yticklabels(['c++', 'mvs', 'Swift', 'Scala'], fontsize=14)
plt.setp(axs[1].get_xticklabels(), fontsize=14)

fig.set_size_inches(5.4, 4.8)
fig.set_dpi(100)
fig.tight_layout()

plt.savefig('plot.pdf', transparent=True)
# plt.show()
