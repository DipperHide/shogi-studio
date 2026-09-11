"""Plot measured displayed poses; rendering pauses remain visible in the chart."""
from pathlib import Path
import json
import matplotlib
matplotlib.use('Agg')
from matplotlib import pyplot as plt

root = Path(__file__).resolve().parents[1]
data = root / 'review/app/chessis28'
scenario = 'wood-capture-0.25'
fig, ax = plt.subplots(figsize=(8.5, 4.3), layout='constrained')
for folder, label, color in [('baseline', '0.27: accumulated frame time', '#b95340'), ('ui', '0.28: displayed-frame clock', '#2563c9')]:
    cases = json.loads((data / folder / 'motion-frames.json').read_text('utf-8'))
    case = next(c for c in cases if c['scenario'] == scenario)
    frames = case['frames']
    ax.step([0] + [f['ms'] for f in frames], [0] + [f['progress'] * 100 for f in frames], where='post', color=color, label=label, linewidth=2)
    ax.plot([f['ms'] for f in frames], [f['progress'] * 100 for f in frames], '.', color=color, markersize=4)
ax.set(title='3D capture: movement shown after a 400 ms render stall', xlabel='Milliseconds after the replay command returned', ylabel='Displayed movement (%)', ylim=(-3, 105))
ax.grid(alpha=.2)
ax.legend(loc='lower right', frameon=False)
fig.savefig(root / 'docs/images/motion28-progress.png', dpi=180)
svg = root / 'docs/images/motion28-progress.svg'
fig.savefig(svg)
svg.write_text('\n'.join(line.rstrip() for line in svg.read_text('utf-8').splitlines()) + '\n', 'utf-8')
