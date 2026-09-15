from pathlib import Path
import sys
sys.path.append(str(Path(__file__).resolve().parent))
from tools.build_app_icon import make_icon_png

img = make_icon_png(192)
out = Path('debug-build-app-icon.png')
img.save(out)
px = img.load()
sample = [px[x, y] for x in range(0, 192, 24) for y in range(0, 192, 24)]
print(out, img.size, img.mode, 'sample_min_max=', min(sample), max(sample))
