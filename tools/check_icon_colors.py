from pathlib import Path
from PIL import Image

for path in [
    Path('android/app/src/main/res/mipmap-mdpi/ic_launcher.png'),
    Path('android/app/src/main/res/mipmap-hdpi/ic_launcher.png'),
    Path('android/app/src/main/res/mipmap-xhdpi/ic_launcher.png'),
    Path('android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png'),
    Path('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png'),
    Path('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_1024.png'),
    Path('android/app/src/main/res/drawable/ic_launcher_foreground.png'),
    Path('android/app/src/main/res/drawable/ic_launcher_background.png'),
]:
    if not path.exists():
        continue
    with Image.open(path) as im:
        px = im.load()
        w, h = im.size
        sample = []
        for x in range(0, w, max(1, w // 8)):
            for y in range(0, h, max(1, h // 8)):
                sample.append(px[x, y])
        print(path, im.size, im.mode, 'sample_min_max=', min(sample), max(sample))
