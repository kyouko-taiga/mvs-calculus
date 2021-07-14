import matplotlib.pyplot as plt
import numpy as np
import os
import pandas
import sys

from .generator.gen import ROOT_DIR
from .normalize import normalize
from scipy import stats

input = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT_DIR, 'results.csv')
normalize(input)
data  = pandas.read_csv(input + ".normalized")

exec_time = data.drop(['bench-name'], axis=1)

args = dict(patch_artist=True, boxprops=dict(facecolor='#ffe5cc'),
            showfliers=False)

plt.boxplot(exec_time, vert=False, widths=0.75, **args)
plt.yticks(ticks=[1, 2, 3, 4], labels=['C++', 'MVS', 'Swift', 'Scala'])
plt.xscale('log')
plt.tight_layout()
plt.savefig('boxplot.pdf', transparent=True, dpi=100)
