"""Package the generated brand mark into Android/Web launcher assets.

Requires Pillow in the development Python environment; no Flutter dependency.
Run from any directory: python scripts/build_icons.py
"""

import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "assets" / "branding"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
BACKGROUND = "#0B0C0E"
source = Image.open(BRAND / "gym-mark.png").convert("RGBA")
# Ignore almost invisible alpha when measuring transparent export padding.
# The actual mark is preserved; only its packaging size/position changes.
bounds = source.getchannel("A").point(lambda a: 255 if a >= 32 else 0).getbbox()
if not bounds:
    raise ValueError("Brand mark is empty")
mark = source.crop(bounds)


def foreground(size, fraction):
    fitted = mark.copy()
    fitted.thumbnail((round(size * fraction), round(size * fraction)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size))
    canvas.alpha_composite(fitted, ((size - fitted.width) // 2, (size - fitted.height) // 2))
    return canvas


def opaque_icon(size):
    result = Image.new("RGBA", (size, size), BACKGROUND)
    result.alpha_composite(foreground(size, 0.72))
    return result.convert("RGB")


assets = []


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)
    assets.append({"file": path.relative_to(ROOT).as_posix(), "size": list(image.size), "mode": image.mode})


for density, scale in [("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)]:
    directory = RES / f"mipmap-{density}"
    save(opaque_icon(round(48 * scale)), directory / "ic_launcher.png")
    # Android adaptive icons use a 108dp layer and a 66dp safe circle.
    adaptive = foreground(round(108 * scale), 0.54)
    save(adaptive, directory / "ic_launcher_foreground.png")
    safe = Image.new("L", adaptive.size)
    draw = ImageDraw.Draw(safe)
    c = adaptive.width / 2
    radius = adaptive.width * 33 / 108
    draw.ellipse((c - radius, c - radius, c + radius, c + radius), fill=255)
    visible = adaptive.getchannel("A").point(lambda a: 255 if a >= 32 else 0)
    assert ImageChops.subtract(visible, safe).getbbox() is None, f"Clipped at {density}"

save(opaque_icon(1024), BRAND / "app-icon.png")
save(opaque_icon(32), ROOT / "web" / "favicon.png")
for size in [192, 512]:
    for prefix in ["Icon", "Icon-maskable"]:
        save(opaque_icon(size), ROOT / "web" / "icons" / f"{prefix}-{size}.png")

# Contact sheet shows the actual Android viewport, masks, and small sizes.
sheet = Image.new("RGB", (840, 400), "#ECECE7")
draw = ImageDraw.Draw(sheet)
viewport = foreground(288, 0.54).crop((48, 48, 240, 240))
for i, kind in enumerate(["circle", "rounded", "square"]):
    tile = Image.new("RGBA", (192, 192), BACKGROUND)
    tile.alpha_composite(viewport)
    mask = Image.new("L", (192, 192))
    painter = ImageDraw.Draw(mask)
    if kind == "circle":
        painter.ellipse((0, 0, 191, 191), fill=255)
    elif kind == "rounded":
        painter.rounded_rectangle((0, 0, 191, 191), radius=44, fill=255)
    else:
        painter.rectangle((0, 0, 191, 191), fill=255)
    sheet.paste(tile, (48 + i * 260, 32), mask)
    draw.text((48 + i * 260, 238), kind, fill="#16181C")
for i, size in enumerate([32, 48, 72, 96]):
    tile = opaque_icon(size)
    sheet.paste(tile, (48 + i * 180, 290))
    draw.text((48 + i * 180 + size + 8, 300), f"{size}px", fill="#16181C")
save(sheet, BRAND / "icon-preview.png")
(BRAND / "icon-assets.json").write_text(json.dumps(assets, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Packaged {len(assets)} assets; adaptive safe-circle checks passed.")
