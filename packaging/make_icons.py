#!/usr/bin/env python3
"""Generate the app icon set.

The glyph is the same Material icon the app shows in its sidebar header
(Icons.graphic_eq_rounded), rendered from Flutter's bundled MaterialIcons font
so the launcher icon and the in-app logo stay identical.
"""
import os
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

GLYPH = 0xF7BD  # Icons.graphic_eq_rounded
ACCENT_TOP = (182, 129, 93)  # #B6815D
ACCENT_BOTTOM = (129, 99, 78)  # #81634E
SIZES = [16, 24, 32, 48, 64, 128, 256, 512]

FONT_RELATIVE = "bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf"


def find_font():
    """Locate the MaterialIcons font inside the Flutter SDK.

    The SDK lands somewhere different depending on how it was installed --
    Homebrew, a git clone, the Google installer -- so follow `flutter` on PATH
    instead of trusting one machine's layout. MEWSIC_MATERIAL_FONT overrides.
    """
    override = os.environ.get("MEWSIC_MATERIAL_FONT")
    if override:
        return override

    flutter = shutil.which("flutter")
    if flutter:
        root = os.path.dirname(os.path.dirname(os.path.realpath(flutter)))
        candidate = os.path.join(root, FONT_RELATIVE)
        if os.path.exists(candidate):
            return candidate

    return os.path.expanduser(f"~/dev/flutter/{FONT_RELATIVE}")


FONT = find_font()


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius, fill=255)
    return mask


def gradient(size):
    """Vertical accent gradient, drawn at full size then masked."""
    img = Image.new("RGB", (1, size))
    px = img.load()
    for y in range(size):
        t = y / max(size - 1, 1)
        px[0, y] = tuple(
            round(ACCENT_TOP[i] + (ACCENT_BOTTOM[i] - ACCENT_TOP[i]) * t) for i in range(3)
        )
    return img.resize((size, size), Image.NEAREST)


def make(size, out_dir):
    # Supersample so the rounded corners and glyph edges stay clean.
    scale = 4 if size <= 128 else 2
    s = size * scale

    base = gradient(s).convert("RGBA")
    base.putalpha(rounded_mask(s, int(s * 0.22)))

    # Fit the glyph to roughly 60% of the tile.
    font = ImageFont.truetype(FONT, int(s * 0.60))
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text((s / 2, s / 2), chr(GLYPH), font=font, fill=(255, 255, 255, 255), anchor="mm")

    base.alpha_composite(layer)
    icon = base.resize((size, size), Image.LANCZOS)

    path = os.path.join(out_dir, f"{size}.png")
    icon.save(path)
    return path


# Android launcher icon densities, and the smaller notification-icon set.
ANDROID_LAUNCHER = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
ANDROID_NOTIFICATION = {
    "drawable-mdpi": 24,
    "drawable-hdpi": 36,
    "drawable-xhdpi": 48,
    "drawable-xxhdpi": 72,
    "drawable-xxxhdpi": 96,
}


def make_notification(size, path):
    """A white glyph on transparency.

    Android tints the status-bar icon itself and only reads the alpha channel,
    so anything but a white silhouette shows up as a grey blob.
    """
    scale = 4
    s = size * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    font = ImageFont.truetype(FONT, int(s * 0.86))
    ImageDraw.Draw(img).text(
        (s / 2, s / 2), chr(GLYPH), font=font, fill=(255, 255, 255, 255), anchor="mm"
    )
    img.resize((size, size), Image.LANCZOS).save(path)
    return path


def write_android(res_dir):
    for folder, size in ANDROID_LAUNCHER.items():
        d = os.path.join(res_dir, folder)
        os.makedirs(d, exist_ok=True)
        make(size, d)
        os.replace(os.path.join(d, f"{size}.png"), os.path.join(d, "ic_launcher.png"))
        print("wrote", os.path.join(d, "ic_launcher.png"))

    for folder, size in ANDROID_NOTIFICATION.items():
        d = os.path.join(res_dir, folder)
        os.makedirs(d, exist_ok=True)
        print("wrote", make_notification(size, os.path.join(d, "ic_notification.png")))


# The sizes macOS asks for in AppIcon.appiconset/Contents.json. 16 through 512
# each appear twice, once at 1x and once as the 2x of the size below it, so one
# file per pixel dimension covers every entry.
MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]


def write_macos(iconset_dir):
    """Fill in AppIcon.appiconset, replacing Flutter's stock logo."""
    for size in MACOS_SIZES:
        make(size, iconset_dir)
        os.replace(
            os.path.join(iconset_dir, f"{size}.png"),
            os.path.join(iconset_dir, f"app_icon_{size}.png"),
        )
        print("wrote", os.path.join(iconset_dir, f"app_icon_{size}.png"))


NOTE_GLYPH = 0xF8ED  # Icons.music_note_rounded


def make_album_placeholder(path, size=512):
    """The stand-in cover shown when a track has no embedded artwork.

    Deliberately unlike the app icon: the notification already shows that as
    its small status icon, and two copies of the same mark read as a bug. This
    matches the neutral tile the app itself draws for a coverless album.
    """
    scale = 2
    s = size * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, s - 1, s - 1], int(s * 0.06), fill=(34, 31, 41, 255))

    font = ImageFont.truetype(FONT, int(s * 0.42))
    d.text((s / 2, s / 2), chr(NOTE_GLYPH), font=font,
           fill=(156, 151, 168, 255), anchor="mm")

    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path)
    return path


def main():
    if not os.path.exists(FONT):
        sys.exit(f"MaterialIcons font not found at {FONT}")

    if len(sys.argv) > 2 and sys.argv[1] == "--android":
        write_android(sys.argv[2])
        return

    if len(sys.argv) > 2 and sys.argv[1] == "--macos":
        write_macos(sys.argv[2])
        return

    if len(sys.argv) > 2 and sys.argv[1] == "--album-placeholder":
        print("wrote", make_album_placeholder(sys.argv[2]))
        return

    out_dir = sys.argv[1] if len(sys.argv) > 1 else "icons"
    os.makedirs(out_dir, exist_ok=True)
    for size in SIZES:
        print("wrote", make(size, out_dir))


if __name__ == "__main__":
    main()
