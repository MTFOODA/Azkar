"""Generate AZKAR raster branding assets from the geometric brand mark.

Requires Pillow. The matching editable vector wordmarks live in
assets/branding/azkar_logo*.svg.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
BRANDING = ROOT / "assets" / "branding"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS_ICONS = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
IOS_SPLASH = ROOT / "ios" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"

EMERALD = "#064E3B"
GOLD = "#D4AF37"
IVORY = "#F8F5EC"
WHITE = "#FFFFFF"
TRANSPARENT = (0, 0, 0, 0)
SUPERSAMPLE = 3


def _scale(value: float, size: int) -> int:
    return round(value * size / 100)


def _cubic(
    start: tuple[float, float],
    first: tuple[float, float],
    second: tuple[float, float],
    end: tuple[float, float],
    steps: int = 18,
) -> list[tuple[float, float]]:
    points = []
    for index in range(steps + 1):
        t = index / steps
        inverse = 1 - t
        x = (
            inverse**3 * start[0]
            + 3 * inverse**2 * t * first[0]
            + 3 * inverse * t**2 * second[0]
            + t**3 * end[0]
        )
        y = (
            inverse**3 * start[1]
            + 3 * inverse**2 * t * first[1]
            + 3 * inverse * t**2 * second[1]
            + t**3 * end[1]
        )
        points.append((x, y))
    return points


def _star_points(cx: float, cy: float, outer: float, inner: float) -> list[tuple[float, float]]:
    points = []
    for index in range(16):
        angle = -math.pi / 2 + index * math.pi / 8
        radius = outer if index % 2 == 0 else inner
        points.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return points


def draw_mark(
    image: Image.Image,
    bounds: tuple[int, int, int, int],
    *,
    foreground: str,
    accent: str,
    knockout: str | None,
) -> None:
    left, top, width, height = bounds
    size = min(width, height)
    scale = size / 100
    origin_x = left + (width - size) / 2
    origin_y = top + (height - size) / 2
    canvas = ImageDraw.Draw(image)

    def point(x: float, y: float) -> tuple[int, int]:
        return (
            round((origin_x + x * scale) * SUPERSAMPLE),
            round((origin_y + y * scale) * SUPERSAMPLE),
        )

    def stroke(points: list[tuple[float, float]], color: str, amount: float) -> None:
        canvas.line(
            [point(x, y) for x, y in points],
            fill=color,
            width=max(1, round(amount * scale * SUPERSAMPLE)),
            joint="curve",
        )

    arch_left = _cubic((22, 86), (22, 68), (22, 57), (22, 45))
    arch_top_left = _cubic((22, 45), (22, 25.7), (34.5, 13), (50, 13))
    arch_top_right = _cubic((50, 13), (65.5, 13), (78, 25.7), (78, 45))
    arch_right = _cubic((78, 45), (78, 57), (78, 68), (78, 86))
    stroke(arch_left + arch_top_left[1:] + arch_top_right[1:] + arch_right[1:], foreground, 5.5)
    stroke([(30, 86), (70, 86)], accent, 4)
    stroke([(39, 78), (61, 78)], foreground, 3)

    if knockout:
        box = (39, 32, 59, 52)
        canvas.ellipse(
            tuple(round((origin_x + coord * scale) * SUPERSAMPLE) for coord in box),
            fill=accent,
        )
        box = (47, 29, 67, 49)
        canvas.ellipse(
            tuple(round((origin_x + coord * scale) * SUPERSAMPLE) for coord in box),
            fill=knockout,
        )
    else:
        crescent = _cubic((44.7, 35.6), (37.2, 37.4), (31.9, 44.1), (31.9, 52))
        crescent += _cubic((31.9, 52), (31.9, 61.2), (39.4, 68.7), (48.6, 68.7))[1:]
        crescent += _cubic((48.6, 68.7), (52.2, 68.7), (55.5, 67.6), (58.2, 65.6))[1:]
        crescent += _cubic((58.2, 65.6), (49.1, 65.4), (41.8, 57.9), (41.8, 48.8))[1:]
        crescent += _cubic((41.8, 48.8), (41.8, 43.5), (44.3, 38.7), (48.2, 35.6))[1:]
        canvas.polygon([point(x, y) for x, y in crescent], fill=accent)

    canvas.ellipse(
        (*point(47, 5), *point(53, 11)),
        fill=accent,
    )
    canvas.polygon(
        [point(x, y) for x, y in _star_points(66, 45, 10.3, 4.7)],
        fill=accent,
    )


def render_mark(
    size: int,
    *,
    background: str | None,
    foreground: str,
    accent: str,
    knockout: str | None = None,
    padding: float = 10,
) -> Image.Image:
    pixel_size = size * SUPERSAMPLE
    image = Image.new("RGBA", (pixel_size, pixel_size), background or TRANSPARENT)
    margin = round(size * padding / 100)
    draw_mark(
        image,
        (margin, margin, size - margin * 2, size - margin * 2),
        foreground=foreground,
        accent=accent,
        knockout=knockout,
    )
    return image.resize((size, size), Image.Resampling.LANCZOS)


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def generate_logo_variants() -> None:
    variants = {
        "azkar_logo_transparent.png": (None, EMERALD, GOLD, TRANSPARENT),
        "azkar_logo_light.png": (IVORY, EMERALD, GOLD, IVORY),
        "azkar_logo_dark.png": (EMERALD, IVORY, GOLD, EMERALD),
        "azkar_logo_full_color.png": (None, EMERALD, GOLD, TRANSPARENT),
        "azkar_logo_monochrome.png": (None, EMERALD, EMERALD, TRANSPARENT),
    }
    for filename, (background, foreground, accent, knockout) in variants.items():
        save_png(
            render_mark(
                1024,
                background=background,
                foreground=foreground,
                accent=accent,
                knockout=knockout,
                padding=13,
            ),
            BRANDING / filename,
        )


def generate_launcher_icons() -> None:
    icon = render_mark(
        1024, background=EMERALD, foreground=IVORY, accent=GOLD, knockout=EMERALD
    )
    save_png(icon, BRANDING / "azkar_icon.png")
    save_png(
        render_mark(432, background=None, foreground=IVORY, accent=GOLD),
        BRANDING / "azkar_icon_foreground.png",
    )
    save_png(
        render_mark(432, background=None, foreground=IVORY, accent=GOLD),
        ANDROID_RES / "drawable-nodpi" / "azkar_icon_foreground.png",
    )
    save_png(
        render_mark(432, background=None, foreground=WHITE, accent=WHITE),
        BRANDING / "azkar_icon_monochrome.png",
    )
    save_png(
        render_mark(432, background=None, foreground=WHITE, accent=WHITE),
        ANDROID_RES / "drawable-nodpi" / "azkar_icon_monochrome.png",
    )
    save_png(
        render_mark(64, background=IVORY, foreground=EMERALD, accent=GOLD, knockout=IVORY),
        ROOT / "web" / "favicon.png",
    )

    web_sizes = {
        "Icon-192.png": (192, 10),
        "Icon-512.png": (512, 10),
        "Icon-maskable-192.png": (192, 25),
        "Icon-maskable-512.png": (512, 25),
    }
    for filename, (size, padding) in web_sizes.items():
        save_png(
            render_mark(
                size,
                background=EMERALD,
                foreground=IVORY,
                accent=GOLD,
                knockout=EMERALD,
                padding=padding,
            ),
            ROOT / "web" / "icons" / filename,
        )

    for density, size in {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }.items():
        save_png(
            render_mark(
                size, background=EMERALD, foreground=IVORY, accent=GOLD,
                knockout=EMERALD, padding=12
            ),
            ANDROID_RES / density / "ic_launcher.png",
        )

    for filename, size in {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }.items():
        save_png(
            render_mark(
                size, background=IVORY, foreground=EMERALD, accent=GOLD,
                knockout=IVORY, padding=11
            ).convert("RGB"),
            IOS_ICONS / filename,
        )

    for filename, width, height in (
        ("LaunchImage.png", 168, 185),
        ("LaunchImage@2x.png", 336, 370),
        ("LaunchImage@3x.png", 504, 555),
    ):
        image = Image.new(
            "RGBA", (width * SUPERSAMPLE, height * SUPERSAMPLE), IVORY
        )
        mark_size = round(min(width, height) * 0.68)
        left = (width - mark_size) // 2
        top = (height - mark_size) // 2
        draw_mark(
            image,
            (left, top, mark_size, mark_size),
            foreground=EMERALD,
            accent=GOLD,
            knockout=IVORY,
        )
        image = image.resize((width, height), Image.Resampling.LANCZOS).convert(
            "RGB"
        )
        save_png(image, IOS_SPLASH / filename)

    splash = render_mark(
        256, background=None, foreground=EMERALD, accent=GOLD, padding=15
    )
    save_png(splash, ANDROID_RES / "drawable-nodpi" / "azkar_splash_logo.png")


def main() -> None:
    generate_logo_variants()
    generate_launcher_icons()
    print("Generated AZKAR branding variants and Android, iOS, and web icons.")


if __name__ == "__main__":
    main()
