# Builds the Windows icons from the macOS app icon, so both builds look the same.
#
#   python3 scripts/make-icons.py
#
# Writes assets/icon.ico (app, installer and shortcuts) and the tray PNGs. Windows
# tray icons are drawn at whatever the display scaling says, so several sizes go in.

import subprocess
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parent / "assets"
ICNS = HERE.parent.parent / "Support" / "AppIcon.icns"

ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]
TRAY_SIZES = [16, 20, 24, 32]


def source() -> Image.Image:
    """The .icns, via sips, which is the only reader for it on a Mac."""
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "icon.png"
        subprocess.run(
            ["sips", "-s", "format", "png", "--out", str(png), str(ICNS)],
            check=True,
            capture_output=True,
        )
        return Image.open(png).convert("RGBA")


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    icon = source()

    ico = ASSETS / "icon.ico"
    icon.save(ico, format="ICO", sizes=[(s, s) for s in ICO_SIZES])
    print(f"{ico.name}  {ico.stat().st_size // 1024} KB  {ICO_SIZES}")

    # The tray sits on the taskbar, which is dark by default and light when the
    # user picks the light theme. The app icon is a dark rounded square with white
    # bars, which disappears on a dark taskbar, so the tray gets the bars alone:
    # white for the dark taskbar, near-black for the light one.
    for name, colour in (("tray", (255, 255, 255, 255)), ("tray-light", (23, 23, 23, 255))):
        for size in TRAY_SIZES:
            bars(size, colour).save(ASSETS / f"{name}@{size}.png")
        bars(32, colour).save(ASSETS / f"{name}.png")
        print(f"{name}.png  {TRAY_SIZES}")


def bars(size: int, colour: tuple[int, int, int, int]) -> Image.Image:
    """The five-bar mark on its own, drawn at 8x and scaled down so the rounded
    ends survive at 16 pixels."""
    scale = 8
    big = size * scale
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))

    from PIL import ImageDraw

    draw = ImageDraw.Draw(image)

    heights = [0.34, 0.60, 0.86, 0.52, 0.28]
    width = big * 0.105
    gap = (big * 0.80 - width * len(heights)) / (len(heights) - 1)
    left = (big - (width * len(heights) + gap * (len(heights) - 1))) / 2

    for index, height in enumerate(heights):
        tall = big * height
        x = left + index * (width + gap)
        y = (big - tall) / 2
        draw.rounded_rectangle(
            [x, y, x + width, y + tall], radius=width / 2, fill=colour
        )

    return image.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    main()
