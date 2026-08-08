#!/usr/bin/env python3
"""Create deterministic App Store screenshot artwork from native Simulator captures."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
FINAL = ROOT / "final"
CANVAS_SIZE = (1320, 2868)
FONT = "/System/Library/Fonts/HelveticaNeue.ttc"
FRAME_ASSET = ROOT / "assets" / "iphone-model.png"

SCREENS = [
    {
        "source": "01-home.png",
        "output": "01-your-fitness.png",
        "headline": "Your fitness,\nall in one place.",
        "subhead": "Workouts, cardio, weight and progress—together.",
        "top": (33, 29, 78),
        "bottom": (9, 12, 32),
        "accent": (126, 111, 255),
    },
    {
        "source": "02-workouts.png",
        "output": "02-every-rep.png",
        "headline": "See every rep\nadd up.",
        "subhead": "Log sets, review volume and stay consistent.",
        "top": (62, 25, 91),
        "bottom": (15, 10, 35),
        "accent": (191, 100, 255),
    },
    {
        "source": "04-runs.png",
        "output": "03-every-workout.png",
        "headline": "Every workout\ncounts.",
        "subhead": "Track runs, walks, rides and more in one history.",
        "top": (8, 72, 78),
        "bottom": (5, 24, 38),
        "accent": (45, 221, 197),
    },
    {
        "source": "05-weight.png",
        "output": "04-progress-visible.png",
        "headline": "Make progress\nvisible.",
        "subhead": "Follow your trend without losing sight of the work.",
        "top": (15, 73, 54),
        "bottom": (7, 27, 28),
        "accent": (78, 226, 146),
    },
    {
        "source": "03-ai.png",
        "output": "05-plan-smarter.png",
        "headline": "Plan smarter.\nTrain your way.",
        "subhead": "Build weekly plans with on-device Apple Intelligence.",
        "top": (19, 54, 112),
        "bottom": (8, 19, 50),
        "accent": (72, 149, 255),
    },
    {
        "source": "06-running-assistant.png",
        "output": "06-run-plan.png",
        "headline": "A run plan that\nfits your life.",
        "subhead": "Choose a goal, follow each session and build momentum.",
        "top": (8, 66, 96),
        "bottom": (5, 21, 43),
        "accent": (54, 190, 255),
    },
]


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT, size=size, index=1 if bold else 0)


def gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    width, height = size
    image = Image.new("RGB", size)
    pixels = image.load()
    for y in range(height):
        ratio = y / max(height - 1, 1)
        color = tuple(round(a + (b - a) * ratio) for a, b in zip(top, bottom))
        for x in range(width):
            pixels[x, y] = color
    return image


def add_glow(canvas: Image.Image, accent: tuple[int, int, int]) -> None:
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    draw.ellipse((-260, -290, 930, 900), fill=(*accent, 92))
    glow = glow.filter(ImageFilter.GaussianBlur(210))
    canvas.paste(glow, (0, 0), glow)


def green_screen_mask(image: Image.Image) -> Image.Image:
    pixels = image.convert("RGB").load()
    mask = Image.new("L", image.size, 0)
    target = mask.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue = pixels[x, y]
            if green > 120 and green > red * 1.45 and green > blue * 1.45:
                target[x, y] = 255
    return mask


def place_screenshot(canvas: Image.Image, screenshot: Image.Image, accent: tuple[int, int, int]) -> None:
    model = Image.open(FRAME_ASSET).convert("RGBA")
    source_green = green_screen_mask(model)
    green_box = source_green.getbbox()
    if green_box is None:
        raise RuntimeError("The iPhone model asset does not contain a keyed screen.")

    padding = (48, 46, 48, 50)
    crop_box = (
        max(0, green_box[0] - padding[0]),
        max(0, green_box[1] - padding[1]),
        min(model.width, green_box[2] + padding[2]),
        min(model.height, green_box[3] + padding[3]),
    )
    model = model.crop(crop_box)
    source_green = source_green.crop(crop_box)
    relative_green = source_green.getbbox()
    if relative_green is None:
        raise RuntimeError("Unable to locate the keyed display after cropping.")

    target_screen_width = 920
    target_screen_height = round(screenshot.height * target_screen_width / screenshot.width)
    scale_x = target_screen_width / (relative_green[2] - relative_green[0])
    scale_y = target_screen_height / (relative_green[3] - relative_green[1])
    model_size = (round(model.width * scale_x), round(model.height * scale_y))
    model = model.resize(model_size, Image.Resampling.LANCZOS)
    source_green = source_green.resize(model_size, Image.Resampling.BILINEAR)

    screen_box = (
        round(relative_green[0] * scale_x),
        round(relative_green[1] * scale_y),
        round(relative_green[2] * scale_x),
        round(relative_green[3] * scale_y),
    )
    screen_size = (screen_box[2] - screen_box[0], screen_box[3] - screen_box[1])
    screenshot = screenshot.convert("RGBA").resize(screen_size, Image.Resampling.LANCZOS)
    screen_mask = Image.new("L", screen_size, 0)
    ImageDraw.Draw(screen_mask).rounded_rectangle(
        (0, 0, screen_size[0] - 1, screen_size[1] - 1), radius=88, fill=255
    )

    device_mask = Image.new("L", model_size, 0)
    ImageDraw.Draw(device_mask).rounded_rectangle(
        (0, 0, model_size[0] - 1, model_size[1] - 1), radius=124, fill=255
    )
    keyed_screen = source_green.filter(ImageFilter.MaxFilter(9)).point(
        lambda value: 255 if value > 50 else 0
    )
    model_alpha = ImageChops.subtract(device_mask, keyed_screen)

    # Remove the generated checkerboard outside the dark titanium body.
    model_pixels = model.load()
    alpha_pixels = model_alpha.load()
    for y in range(model.height):
        for x in range(model.width):
            red, green, blue, _ = model_pixels[x, y]
            if min(red, green, blue) > 225 and max(red, green, blue) - min(red, green, blue) < 18:
                alpha_pixels[x, y] = 0
    model.putalpha(model_alpha)

    device_x = (CANVAS_SIZE[0] - model.width) // 2
    device_y = 700
    screen_position = (device_x + screen_box[0], device_y + screen_box[1])

    shadow_mask = device_mask.filter(ImageFilter.GaussianBlur(42))
    shadow = Image.new("RGBA", model_size, (0, 0, 0, 190))
    shadow.putalpha(shadow_mask.point(lambda value: round(value * 0.28)))
    canvas.paste(shadow, (device_x, device_y + 24), shadow)
    canvas.paste(screenshot, screen_position, screen_mask)
    canvas.paste(model, (device_x, device_y), model)


def render_screen(item: dict[str, object]) -> Image.Image:
    source = RAW / str(item["source"])
    screenshot = Image.open(source)
    canvas = gradient(CANVAS_SIZE, item["top"], item["bottom"])
    add_glow(canvas, item["accent"])
    draw = ImageDraw.Draw(canvas)

    draw.text((92, 78), "PACE & PLATES", font=font(36, bold=True), fill=(*item["accent"], 255))
    draw.multiline_text(
        (88, 142),
        str(item["headline"]),
        font=font(112, bold=True),
        fill=(255, 255, 255),
        spacing=0,
    )
    draw.text(
        (92, 460),
        str(item["subhead"]),
        font=font(39),
        fill=(224, 228, 243),
    )
    place_screenshot(canvas, screenshot, item["accent"])
    return canvas.convert("RGB")


def create_contact_sheet(outputs: list[Path]) -> None:
    thumb_width = 330
    thumb_height = round(CANVAS_SIZE[1] * thumb_width / CANVAS_SIZE[0])
    sheet = Image.new("RGB", (thumb_width * 3, thumb_height * 2), (10, 10, 14))
    for index, path in enumerate(outputs):
        thumb = Image.open(path).convert("RGB").resize((thumb_width, thumb_height), Image.Resampling.LANCZOS)
        sheet.paste(thumb, ((index % 3) * thumb_width, (index // 3) * thumb_height))
    sheet.save(ROOT / "contact-sheet.jpg", quality=92, optimize=True)


def main() -> None:
    FINAL.mkdir(parents=True, exist_ok=True)
    outputs: list[Path] = []
    manifest = {
        "app": "Pace & Plates",
        "version": "2.4",
        "device_class": "iPhone 6.9-inch",
        "dimensions": list(CANVAS_SIZE),
        "format": "PNG, RGB, no alpha",
        "hardware_model": "assets/iphone-model.png",
        "composition": "Generated iPhone hardware asset with deterministic, unmodified Simulator UI compositing",
        "screenshots": [],
    }
    for item in SCREENS:
        output = FINAL / str(item["output"])
        render_screen(item).save(output, format="PNG", optimize=True)
        outputs.append(output)
        manifest["screenshots"].append(
            {
                "file": output.name,
                "source": f"raw/{item['source']}",
                "headline": item["headline"],
                "subhead": item["subhead"],
            }
        )
    (ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    create_contact_sheet(outputs)


if __name__ == "__main__":
    main()
