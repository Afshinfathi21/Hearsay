"""Generate the tileable PBR textures for Materials/Textures/ (numpy + Pillow + scipy).

Conventions
  * Albedo: sRGB PNG.   ORM: R = ambient occlusion, G = roughness, B = metallic (linear).
  * Normal: OpenGL convention (green = up), which is what Godot expects.
  * 1024 px maps cover 4 m (256 px/m, the Phase 1 target). All maps tile seamlessly
    (noise is built with the FFT, so it wraps by construction).
Run: python3 make_textures.py
"""
import os
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets/common/materials/Textures")
os.makedirs(OUT, exist_ok=True)


# ---------------------------------------------------------------- noise tools
def norm(a):
    return (a - a.mean()) / (a.std() + 1e-9)


def fnoise(n, beta=2.0, seed=0, lo=0.0, hi=None, aniso=(1.0, 1.0)):
    """Tileable noise with power spectrum ~ 1/f^beta, band-limited to [lo, hi]
    cycles per tile. aniso < 1 along an axis stretches features along that axis."""
    rng = np.random.default_rng(seed)
    F = np.fft.fft2(rng.standard_normal((n, n)))
    fy = np.fft.fftfreq(n)[:, None] * n
    fx = np.fft.fftfreq(n)[None, :] * n
    r = np.sqrt((fx / aniso[0]) ** 2 + (fy / aniso[1]) ** 2)
    r[0, 0] = 1.0
    filt = r ** (-beta / 2.0)
    rr = np.sqrt(fx ** 2 + fy ** 2)
    if hi:
        filt = filt * (rr <= hi)
    filt = filt * (rr >= lo)
    filt[0, 0] = 0.0
    return norm(np.fft.ifft2(F * filt).real)


def scratches(n, count, seed, length=(20, 140), width=1):
    """Random thin lines, drawn with wrap-around so the tile stays seamless."""
    rng = np.random.default_rng(seed)
    img = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(img)
    for _ in range(count):
        x, y = rng.uniform(0, n, 2)
        ang = rng.uniform(0, np.pi)
        ln = rng.uniform(*length)
        dx, dy = np.cos(ang) * ln, np.sin(ang) * ln
        v = int(rng.uniform(90, 255))
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                d.line([(x + ox, y + oy), (x + dx + ox, y + dy + oy)], fill=v, width=width)
    return np.asarray(img, dtype=np.float32) / 255.0


def srgb(hexc):
    h = hexc.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], dtype=np.float32)


def lerp(a, b, t):
    return a + (b - a) * t[..., None] if a.ndim == 3 else a + (b - a) * t


def normal_map(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5      # d/d(row); v points up
    nx, ny, nz = -dx * strength, dy * strength, np.ones_like(h)
    L = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    return np.stack([nx / L, ny / L, nz / L], -1) * 0.5 + 0.5


def blur(a, s):
    return ndimage.gaussian_filter(a, s, mode="wrap")


def save(name, albedo, ao, rough, metal, height, nstrength):
    def png(arr, suffix):
        Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8)).save(
            os.path.join(OUT, "%s_%s.png" % (name, suffix)), optimize=True)
    png(albedo, "albedo")
    png(np.stack([ao, rough, metal], -1), "orm")
    png(normal_map(height, nstrength), "normal")
    print("wrote", name, albedo.shape[0], "px")


# ------------------------------------------------------------------ materials
def concrete_rough(n=1024):
    mott = fnoise(n, 2.6, 1, 1, 12)
    mid = fnoise(n, 1.8, 2, 8, 80)
    fine = fnoise(n, 0.6, 3, 60, 500)
    stain = fnoise(n, 2.2, 5, 1, 8, aniso=(1.0, 0.05))          # vertical streaks
    pores = np.clip((fnoise(n, 0.3, 4, 100, 500) - 1.9) * 2.0, 0, 1)
    base = srgb("#7B8085")
    shade = 1 + 0.07 * mott + 0.04 * mid + 0.025 * fine + 0.03 * stain
    albedo = base[None, None, :] * (shade * (1 - 0.35 * pores))[..., None]
    height = 0.3 * mott + 0.6 * mid + 0.4 * fine - 2.5 * pores
    rough = 0.90 + 0.03 * mid + 0.05 * pores
    ao = 1 - 0.55 * blur(pores, 1.5) - 0.04 * np.clip(-mid, 0, 2)
    save("concrete_rough", albedo, np.clip(ao, 0.5, 1), np.clip(rough, 0.75, 0.98),
         np.zeros((n, n)), height, 0.9)


def concrete_painted(n=1024):
    mott = fnoise(n, 2.5, 10, 1, 8)
    peel = fnoise(n, 0.8, 11, 40, 400)                           # orange-peel texture
    drips = fnoise(n, 2.0, 12, 1, 10, aniso=(1.0, 0.04))
    chip = fnoise(n, 1.6, 13, 6, 60)
    mask = np.clip((chip - 1.75) * 6.0, 0, 1)                    # ~3% bare concrete
    painted = srgb("#596168")[None, None, :] * (
        1 + 0.03 * mott + 0.025 * peel - 0.04 * np.clip(drips, 0, 3))[..., None]
    bare = srgb("#7B8085")[None, None, :] * (1 + 0.06 * fnoise(n, 1.5, 14, 20, 200))[..., None]
    albedo = lerp(painted, bare, mask)
    rough = lerp(0.66 + 0.05 * peel, 0.88 + 0 * peel, mask)
    height = 0.25 * peel - 1.4 * mask + 0.1 * mott
    ao = 1 - 0.35 * np.clip(blur(mask, 3) - mask, 0, 1) * 3
    save("concrete_painted", albedo, np.clip(ao, 0.6, 1), np.clip(rough, 0.5, 0.95),
         np.zeros((n, n)), height, 1.8)


def steel_brushed(n=1024):
    streak = fnoise(n, 1.0, 21, 2, n // 2, aniso=(0.03, 1.0))   # long along X: brushing direction
    streak2 = fnoise(n, 0.6, 22, 2, 300, aniso=(0.02, 1.0))
    mott = fnoise(n, 2.5, 23, 1, 6)
    sc = scratches(n, 70, 24)
    base = srgb("#4B5258")
    shade = 1 + 0.10 * streak + 0.05 * streak2 + 0.05 * mott + 0.30 * sc
    albedo = base[None, None, :] * shade[..., None]
    rough = 0.45 + 0.06 * streak2 - 0.10 * sc + 0.02 * mott
    metal = 0.65 + 0.03 * mott
    height = 0.25 * streak + 0.2 * streak2 - 0.7 * sc
    ao = 1 - 0.05 * np.clip(-streak, 0, 2)
    save("steel_brushed", albedo, ao, np.clip(rough, 0.3, 0.7), np.clip(metal, 0.55, 0.75),
         height, 0.55)


def paint_worn(n=1024):
    dirt = fnoise(n, 2.4, 33, 1, 7)
    chip = fnoise(n, 1.5, 31, 4, 90)
    fine = fnoise(n, 0.5, 32, 80, 500)
    mask = np.clip((chip - 1.40) * 5.0, 0, 1)
    mask = np.maximum(mask, np.clip((fine - 2.2) * 3.0, 0, 1) * 0.9)
    paint = srgb("#B8B5AB")[None, None, :] * (1 + 0.05 * dirt - 0.10 * np.clip(dirt - 0.8, 0, 2))[..., None]
    under = srgb("#3A3F44")[None, None, :] * (1 + 0.15 * fnoise(n, 1.0, 34, 10, 250))[..., None]
    albedo = lerp(paint, under, mask)
    rough = lerp(0.72 + 0.04 * fine, 0.45 + 0 * fine, mask)
    metal = mask * 0.6
    height = -1.0 * mask + 0.1 * fine
    ao = 1 - 0.4 * np.clip(blur(mask, 2) - mask, 0, 1) * 3
    save("paint_worn", albedo, np.clip(ao, 0.6, 1), np.clip(rough, 0.35, 0.9), metal, height, 1.8)


def rubber(n=512):
    fine = fnoise(n, 0.7, 51, 30, 250)
    mott = fnoise(n, 2.4, 52, 1, 8)
    albedo = srgb("#17191B")[None, None, :] * (1 + 0.14 * fine + 0.10 * mott)[..., None]
    rough = 0.85 + 0.04 * fine
    height = 0.5 * fine + 0.2 * mott
    save("rubber", albedo, np.ones((n, n)) - 0.03 * np.clip(-fine, 0, 2), np.clip(rough, 0.7, 0.95),
         np.zeros((n, n)), height, 2.5)


def fabric(n=512, threads=24):
    """Plain weave. Albedo is a neutral light grey: players' colours are applied
    as albedo_color in Godot, so one set of maps serves every colour."""
    y, x = np.mgrid[0:n, 0:n] / n
    tx, ty = x * threads, y * threads
    fx, fy = tx - np.floor(tx), ty - np.floor(ty)
    over = ((np.floor(tx) + np.floor(ty)) % 2) == 0
    warp, weft = np.sin(np.pi * fx) ** 0.8, np.sin(np.pi * fy) ** 0.8
    h = np.where(over, warp, weft) + 0.15 * fnoise(n, 0.8, 61, 20, 200)
    albedo = (0.78 + 0.12 * (h - h.mean()) + 0.04 * fnoise(n, 2.0, 62, 1, 10))
    albedo = np.stack([albedo] * 3, -1)
    ao = 1 - 0.35 * np.clip(0.6 - h, 0, 1)
    save("fabric", albedo, ao, 0.90 + 0.04 * (h - h.mean()), np.zeros((n, n)), h, 3.0)


def glass_frosted(n=512):
    h = fnoise(n, 0.4, 41, 60, 250)
    Image.fromarray((normal_map(h, 1.2) * 255 + 0.5).astype(np.uint8)).save(
        os.path.join(OUT, "glass_frosted_normal.png"), optimize=True)
    print("wrote glass_frosted_normal", n, "px")


def screen_scanlines(n=256):
    rows = np.where((np.arange(n) % 4) < 2, 1.0, 0.72)[:, None] * np.ones((1, n))
    yy, xx = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    vignette = 1 - 0.18 * (np.abs(xx) ** 3 + np.abs(yy) ** 3)
    e = np.clip(rows * vignette, 0, 1)
    Image.fromarray((np.stack([e] * 3, -1) * 255 + 0.5).astype(np.uint8)).save(
        os.path.join(OUT, "screen_scanlines_emission.png"), optimize=True)
    print("wrote screen_scanlines_emission", n, "px")


if __name__ == "__main__":
    concrete_rough()
    concrete_painted()
    steel_brushed()
    paint_worn()
    rubber()
    fabric()
    glass_frosted()
    screen_scanlines()
