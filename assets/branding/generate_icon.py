"""
Generates the TrikeKoTo launcher icon set.

Outputs:
  icon.png            — 1024x1024 full background, used by flutter_launcher_icons
  icon_foreground.png — 1024x1024 transparent foreground for adaptive Android 8+ icons
  splash.png          — 1024x1024 with smaller mark, used by flutter_native_splash
  splash_branding.png — wide brandmark for the bottom of the splash

Run from the repo root:
    python assets/branding/generate_icon.py

Idempotent — overwrites existing files. Re-run any time the brand changes.
"""

from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

# ── Brand palette (must mirror lib/core/theme.dart) ───────────────────────────
NAVY = (15, 23, 42)        # AppColors.background  #0F172A
AMBER = (245, 158, 11)     # AppColors.accent      #F59E0B
WHITE = (248, 250, 252)    # AppColors.text        #F8FAFC
NAVY_DEEP = (8, 13, 26)    # one shade darker for the splash

OUT_DIR = Path(__file__).parent

SIZE = 1024


def draw_monogram(draw: ImageDraw.ImageDraw, cx: int, cy: int, scale: float, color, bg_color):
    """Draws a clean 'tk' monogram with a tricycle-wheel accent dot.

    We tried a literal tricycle silhouette first — it kept reading as a
    wagon at 48dp because three same-size wheels in a row don't parse as
    "trike" without context. A typographic mark is more legible and more
    distinctively branded; the wheel dot under the 'k' keeps the
    transport theme without fighting the lettering.
    """
    s = scale

    # Pick the heaviest available bold font; fall back to PIL default.
    font_paths = [
        "C:/Windows/Fonts/segoeuib.ttf",   # Segoe UI Bold
        "C:/Windows/Fonts/arialbd.ttf",    # Arial Bold
        "C:/Windows/Fonts/calibrib.ttf",   # Calibri Bold
    ]
    font_size = int(620 * s)
    font = None
    for p in font_paths:
        try:
            font = ImageFont.truetype(p, font_size)
            break
        except OSError:
            continue
    if font is None:
        font = ImageFont.load_default()

    text = "tk"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]

    # Center the text optical bounds, then nudge up slightly so the wheel
    # dot below it doesn't push the visual centre below the canvas centre.
    tx = cx - tw // 2 - bbox[0]
    ty = cy - th // 2 - bbox[1] - int(30 * s)
    draw.text((tx, ty), text, fill=color, font=font)

    # Wheel accent — a single solid dot under the 'k' that hints at the
    # sidecar wheel of a Filipino tricycle. Position it so it sits just
    # below the baseline, slightly right of centre.
    dot_r = int(70 * s)
    dot_cx = cx + int(190 * s)
    dot_cy = cy + int(330 * s)
    draw.ellipse(
        [dot_cx - dot_r, dot_cy - dot_r, dot_cx + dot_r, dot_cy + dot_r],
        fill=color,
    )
    # Inner hub — same colour as background so the wheel "reads" as a tire
    inner_r = int(24 * s)
    draw.ellipse(
        [
            dot_cx - inner_r,
            dot_cy - inner_r,
            dot_cx + inner_r,
            dot_cy + inner_r,
        ],
        fill=bg_color,
    )


# Backwards-compat alias so callers can keep using the old name.
def draw_tricycle(draw, cx, cy, scale, color, hub_color):
    draw_monogram(draw, cx, cy, scale, color=color, bg_color=hub_color)


def make_full_icon():
    """Solid navy background + amber tricycle mark — the legacy/full icon."""
    img = Image.new("RGB", (SIZE, SIZE), NAVY)
    draw = ImageDraw.Draw(img)
    # Center the tricycle's bounding box in the canvas (slightly above middle
    # so the wheels visually balance the roof).
    draw_tricycle(
        draw,
        cx=SIZE // 2,
        cy=SIZE // 2 - 20,
        scale=0.95,
        color=AMBER,
        hub_color=NAVY,
    )
    img.save(OUT_DIR / "icon.png", "PNG")
    print("[ok] icon.png")


def make_adaptive_foreground():
    """Transparent background, amber mark sized to the safe zone (~66%).

    Android 8+ adaptive icons crop the foreground into circle, square,
    squircle, or teardrop depending on the launcher. The mark must fit
    inside the inner 66% of the canvas so it's never clipped — we use a
    solid navy disc as the hub fill so the wheels stay visible regardless
    of which background colour the launcher composites behind us.
    """
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw_tricycle(
        draw,
        cx=SIZE // 2,
        cy=SIZE // 2,
        scale=0.62,
        color=AMBER,
        hub_color=NAVY,
    )
    img.save(OUT_DIR / "icon_foreground.png", "PNG")
    print("[ok] icon_foreground.png")


def make_splash():
    """Splash background image — slightly darker navy with the same mark."""
    img = Image.new("RGB", (SIZE, SIZE), NAVY_DEEP)
    draw = ImageDraw.Draw(img)
    draw_tricycle(
        draw,
        cx=SIZE // 2,
        cy=SIZE // 2,
        scale=0.80,
        color=AMBER,
        hub_color=NAVY_DEEP,
    )
    img.save(OUT_DIR / "splash.png", "PNG")
    print("[ok] splash.png")


def make_splash_branding():
    """Wide wordmark for the bottom of the splash screen."""
    img = Image.new("RGBA", (1200, 200), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    text = "TrikeKoTo"

    # Try to use a real bold font; fall back to PIL's default if not present.
    font = None
    candidates = [
        "C:/Windows/Fonts/segoeuib.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/seguisb.ttf",
    ]
    for path in candidates:
        try:
            font = ImageFont.truetype(path, 96)
            break
        except OSError:
            continue
    if font is None:
        font = ImageFont.load_default()

    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    draw.text(
        ((1200 - tw) // 2 - bbox[0], (200 - th) // 2 - bbox[1]),
        text,
        fill=WHITE,
        font=font,
    )
    img.save(OUT_DIR / "splash_branding.png", "PNG")
    print("[ok] splash_branding.png")


if __name__ == "__main__":
    make_full_icon()
    make_adaptive_foreground()
    make_splash()
    make_splash_branding()
    print("Done. Run flutter_launcher_icons + flutter_native_splash next.")
