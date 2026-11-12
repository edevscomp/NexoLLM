"""Composes NexoLLM's README showcase media onto an atmospheric desktop wallpaper
with real frosted-glass blur, soft elevation shadows, and a crisp 1pt specular rim.

Usage: python3 scripts/readme_media.py <render_dir> <out_dir>
Requires Pillow (PIL).
"""
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

render_dir = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
out_dir.mkdir(parents=True, exist_ok=True)


def wallpaper(width: int, height: int, seed_shift: float = 0.0) -> Image.Image:
    """Renders a rich, atmospheric multi-light desktop wallpaper (indigo, rose-violet, cyan)."""
    sw, sh = max(32, width // 8), max(32, height // 8)
    small = Image.new("RGB", (sw, sh))
    pixels = small.load()
    lights = [
        ((0.17 + seed_shift * 0.05, 0.20), (88, 76, 198), 0.76),
        ((0.84 - seed_shift * 0.04, 0.84), (182, 76, 128), 0.70),
        ((0.80, 0.12 + seed_shift * 0.04), (42, 126, 176), 0.56),
        ((0.46, 0.52), (62, 74, 148), 0.50),
    ]
    aspect = height / width
    for y in range(sh):
        v = y / sh
        for x in range(sw):
            u = x / sw
            c0 = 20.0 + 10.0 * v
            c1 = 22.0 + 8.0 * v
            c2 = 42.0 + 14.0 * v
            for (cx, cy), (tr, tg, tb), reach in lights:
                dist = math.hypot(u - cx, (v - cy) * aspect)
                glow = max(0.0, 1.0 - dist / reach) ** 2
                k = glow * 0.78
                c0 += (tr - c0) * k
                c1 += (tg - c1) * k
                c2 += (tb - c2) * k
            pixels[x, y] = (int(c0), int(c1), int(c2))
    return small.resize((width, height), Image.BICUBIC).filter(ImageFilter.GaussianBlur(14))


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def place(canvas: Image.Image, panel: Image.Image, x: int, y: int, radius: int = 30, glass_blend: float = 0.64):
    """Composites `panel` onto `canvas` at (x, y) as a frosted glass window with soft drop shadow and 1pt rim."""
    w, h = panel.size
    r = min(radius, h // 2)
    mask = rounded_mask((w, h), r)

    # Soft multi-radius elevation shadow
    pad = 96
    sh_box = Image.new("L", (w + pad * 2, h + pad * 2), 0)
    sh_box.paste(mask.point(lambda val: int(val * 0.58)), (pad, pad + 22))
    sh_blur = sh_box.filter(ImageFilter.GaussianBlur(30))
    black_patch = Image.new("RGB", sh_blur.size, (0, 0, 0))
    canvas.paste(black_patch, (x - pad, y - pad), sh_blur)

    # Frosted backdrop under the window
    box = (x, y, x + w, y + h)
    under = canvas.crop(box).filter(ImageFilter.GaussianBlur(42))
    frosted = Image.blend(under, Image.new("RGB", (w, h), (24, 26, 36)), glass_blend)
    frosted.paste(panel, (0, 0), panel)
    canvas.paste(frosted, (x, y), mask)

    # Crisp subtle specular rim (2px at 2x = 1pt)
    rim = Image.new("L", (w, h), 0)
    ImageDraw.Draw(rim).rounded_rectangle([0, 0, w - 1, h - 1], radius=r, outline=48, width=2)
    canvas.paste(Image.new("RGB", (w, h), (255, 255, 255)), (x, y), rim)


def load_rgba(name: str) -> Image.Image:
    return Image.open(render_dir / name).convert("RGBA")


# 1. Animated hero loop: `live.gif` (15 fps, shared palette with zero dither so text stays razor sharp)
demo_frames = sorted(render_dir.glob("demo-*.png"))
if len(demo_frames) > 1:
    first = Image.open(demo_frames[0]).convert("RGBA")
    pad_x, pad_y = 110, 96
    base = wallpaper(first.width + pad_x * 2, first.height + pad_y * 2)
    shots: list[Image.Image] = []
    for path in demo_frames:
        shot = base.copy()
        place(shot, Image.open(path).convert("RGBA"), pad_x, pad_y, radius=30, glass_blend=0.62)
        shots.append(shot.resize((shot.width // 2, shot.height // 2), Image.LANCZOS))
    # Build a 255-color MEDIANCUT palette (leaving index 255 for GIF89a transparency) from key states
    sample_indices = [0, min(18, len(shots) - 1), min(42, len(shots) - 1)]
    strip = Image.new("RGB", (shots[0].width, shots[0].height * len(sample_indices)))
    for i, idx in enumerate(sample_indices):
        strip.paste(shots[idx], (0, i * shots[0].height))
    palette = strip.quantize(colors=255, method=Image.MEDIANCUT, dither=Image.NONE)
    stills = [shot.quantize(palette=palette, dither=Image.NONE) for shot in shots]
    stills[0].save(
        out_dir / "live.gif",
        save_all=True,
        append_images=stills[1:],
        duration=60,
        loop=0,
        optimize=False,
    )
    print(f"Wrote {out_dir / 'live.gif'} ({len(stills)} frames)")

# 2. `overlays.png`: Bento showcase of NexoLLM's 4 floating surfaces on one atmospheric wallpaper
hero = load_rgba("glass-hero-dark.png")
alts = load_rgba("glass-alternatives-dark.png")
qmenu = load_rgba("glass-quickmenu-dark.png")
lookup = load_rgba("glass-lookup-dark.png")

edge = 110
col_gap = 86
row_gap = 82
left_h = hero.height + row_gap + alts.height
right_h = qmenu.height + row_gap + lookup.height
canvas_w = edge * 2 + hero.width + col_gap + qmenu.width
canvas_h = edge * 2 + max(left_h, right_h)

bento = wallpaper(canvas_w, canvas_h, seed_shift=0.3)
left_y0 = edge + (max(left_h, right_h) - left_h) // 2
right_y0 = edge + (max(left_h, right_h) - right_h) // 2

place(bento, hero, edge, left_y0, radius=30, glass_blend=0.62)
place(bento, alts, edge, left_y0 + hero.height + row_gap, radius=30, glass_blend=0.62)
place(bento, qmenu, edge + hero.width + col_gap, right_y0, radius=30, glass_blend=0.62)
place(bento, lookup, edge + hero.width + col_gap, right_y0 + qmenu.height + row_gap, radius=30, glass_blend=0.62)
bento.resize((bento.width // 2, bento.height // 2), Image.LANCZOS).save(out_dir / "overlays.png", optimize=True)
print(f"Wrote {out_dir / 'overlays.png'}")

# 3. `insights.png`: Soft pastel stacked histogram + hover tooltip + Words by App on wallpaper
insights = load_rgba("pane-statistics-dark.png")
ins_canvas = wallpaper(insights.width + 240, insights.height + 220, seed_shift=0.6)
place(ins_canvas, insights, 120, 110, radius=32, glass_blend=0.70)
ins_canvas.resize((ins_canvas.width // 2, ins_canvas.height // 2), Image.LANCZOS).save(out_dir / "insights.png", optimize=True)
print(f"Wrote {out_dir / 'insights.png'}")

# 4. `settings.png`: Side-by-side Models + Context/Awareness windows on wallpaper (like ftop's settings.png)
models = load_rgba("pane-models-dark.png")
context = load_rgba("pane-context-dark.png")
s_edge, s_gap = 110, 88
s_canvas = wallpaper(models.width + context.width + s_gap + s_edge * 2, models.height + s_edge * 2, seed_shift=-0.4)
place(s_canvas, models, s_edge, s_edge, radius=32, glass_blend=0.70)
place(s_canvas, context, s_edge + models.width + s_gap, s_edge, radius=32, glass_blend=0.70)
s_canvas.resize((s_canvas.width // 2, s_canvas.height // 2), Image.LANCZOS).save(out_dir / "settings.png", optimize=True)
print(f"Wrote {out_dir / 'settings.png'}")

# 5. `memory.png`: Memory & Per-App Style pane on wallpaper
personalization = load_rgba("pane-personalization-dark.png")
m_canvas = wallpaper(personalization.width + 240, personalization.height + 220, seed_shift=0.9)
place(m_canvas, personalization, 120, 110, radius=32, glass_blend=0.70)
m_canvas.resize((m_canvas.width // 2, m_canvas.height // 2), Image.LANCZOS).save(out_dir / "memory.png", optimize=True)
print(f"Wrote {out_dir / 'memory.png'}")
