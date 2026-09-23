"""生成 DSHM 黑白极简图标"""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"
SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def make_icon(size: int) -> Image.Image:
    """白色圆角背景 + 黑色 DSHM 文字"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 白色圆角矩形背景
    r = size // 6
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=(255, 255, 255, 255))

    # 尝试加载字体，fallback 到默认
    font_size = int(size * 0.28)
    try:
        font = ImageFont.truetype("arial.ttf", font_size)
    except OSError:
        try:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", font_size)
        except OSError:
            font = ImageFont.load_default()

    # 黑色 "DSHM" 文字
    text = "DSHM"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = (size - tw) / 2
    y = (size - th) / 2 - bbox[1]
    draw.text((x, y), text, fill=(0, 0, 0, 255), font=font)

    return img


def main():
    for density, sz in SIZES.items():
        out_dir = RES / f"mipmap-{density}"
        out_dir.mkdir(parents=True, exist_ok=True)
        icon = make_icon(sz)
        icon.save(out_dir / "ic_launcher.png")
        print(f"  {density}: {sz}x{sz}")

    # adaptive foreground (512x512, 留 padding)
    adp_dir = RES / "mipmap-anydpi-v26"
    adp_dir.mkdir(parents=True, exist_ok=True)
    fg = make_icon(512)
    fg.save(adp_dir / "ic_launcher_1024.png")
    print(f"  adaptive foreground: 512x512")
    print("Done!")


if __name__ == "__main__":
    main()
