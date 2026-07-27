"""Turns the images/ folder into the page.

Run by .github/workflows/vibes.yml on every push that touches images/. You
shouldn't need to run it yourself, but it works locally too:

    pip install pillow pillow-heif
    python3 scripts/vibes.py

Two jobs. It re-encodes anything that isn't already a clean WebP, replacing the
original in place — phone photos are ~4MB each and carry the GPS coordinates of
where they were taken, and this page is public, so neither the bulk nor the
metadata should survive contact with the internet. The re-encode drops both.

"Clean" is doing real work in that sentence: a WebP can carry EXIF too, and
plenty of cameras and download buttons emit one. So an uploaded .webp is only
left alone if it has no EXIF and isn't oversized — which is exactly the state
this script leaves its own output in, so re-runs are a no-op rather than a
slow generational quality loss.

Anything that can't be decoded is deleted rather than left alone, and its name
is recorded in .vibes-rejected so the workflow can go red and say so. Leaving it
would mean an undecodable file — plausibly a HEIC full of GPS that Pillow
couldn't open — sitting in a public repo, which is the one outcome worth
failing loudly over.

Then it writes image_widths_heights.json, which is the list index.html reads to
lay the page out. Dimensions come from the encoded file rather than the source,
so the list always describes the images actually being served.
"""

import io
import json
import sys
import unicodedata
from pathlib import Path

from PIL import Image, ImageOps

try:
    from pillow_heif import register_heif_opener
except ImportError:
    pass  # only needed for iPhone HEICs; the workflow installs it
else:
    register_heif_opener()

ROOT = Path(__file__).resolve().parent.parent
IMAGES = ROOT / "images"
REJECTED = ROOT / ".vibes-rejected"
MAX_EDGE = 1400  # the page draws these ~250-500px wide; 1400 covers retina
QUALITY = 82
SOURCES = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif", ".gif",
           ".bmp", ".tiff", ".tif", ".avif"}


def slug(name):
    """ASCII only, deliberately. "café.jpg" keeps its accent through Python's
    isalnum(), then macOS writes the filename decomposed and Linux writes it
    composed — so the name in the JSON and the name on the server stop matching
    and the image 404s on a machine that isn't the one it was uploaded from."""
    flat = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    keep = "".join(c if c.isalnum() or c in "-_" else "-" for c in flat)
    return "-".join(filter(None, keep.split("-"))).lower() or "image"


def is_clean_webp(f):
    """True if this is already what encode() would produce: WebP, no metadata, in size.

    Lets re-runs skip work without re-encoding a re-encode, while still catching
    a .webp that arrived from a camera or a download with its metadata intact.

    Checking EXIF alone is not enough, and that mistake shipped: a WebP can carry
    GPS in an XMP packet with an empty EXIF block, and such a file was skipped
    byte-for-byte and published with its coordinates readable. Anything Pillow
    surfaces in im.info — xmp, icc_profile, a stray exif key — disqualifies it.

    The suffix test is deliberately case-sensitive. "PHOTO.WEBP" is not a name
    encode() would ever produce, and the glob that builds the page's list only
    matches lowercase — so a skipped .WEBP would sit in a public repo un-stripped
    and invisible. Let it fall through and be re-encoded under a name we chose.
    """
    if f.suffix != ".webp":
        return False
    try:
        with Image.open(f) as im:
            exif = im.getexif()
            metadata = {k for k in im.info if k not in ("background", "loop")}
            return not len(exif) and not exif.get_ifd(0x8825) \
                and not metadata and max(im.size) <= MAX_EDGE
    except Exception:
        return False


def encode(src):
    with Image.open(src) as im:
        im = ImageOps.exif_transpose(im)  # else phone photos land sideways
        if im.mode not in ("RGB", "RGBA"):
            im = im.convert("RGBA" if "A" in im.getbands() else "RGB")
        if max(im.size) > MAX_EDGE:
            im.thumbnail((MAX_EDGE, MAX_EDGE), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "WEBP", quality=QUALITY, method=6)
    return buf.getvalue()


def free_name(stem, taken):
    base = slug(stem)
    dest = IMAGES / f"{base}.webp"
    n = 2
    while dest.exists() or dest in taken:
        dest = IMAGES / f"{base}-{n}.webp"
        n += 1
    taken.add(dest)
    return dest


def main():
    IMAGES.mkdir(exist_ok=True)
    REJECTED.unlink(missing_ok=True)

    rejected, taken = [], set()
    # rglob, not iterdir: github.com's uploader keeps the folder structure when you
    # drag a folder on, so a whole album lands as images/Cornwall 2026/*.jpg. A
    # top-level walk never sees those files — they were committed to a public repo
    # as untouched originals, GPS and all, and no later run ever cleaned them up.
    #
    # Only the basename is kept. Folding the folder name in would be tidier to read
    # and would put "ediya-wedding-nov-2025-" in a public URL; free_name already
    # handles two photos arriving with the same name.
    for src in sorted(IMAGES.rglob("*"), key=lambda p: str(p)):
        if not src.is_file():
            continue

        # A dot-name can't be published (the page's list skips it) and can't be
        # checked, so leaving it means an unexamined file in a public folder.
        if any(part.startswith(".") for part in src.relative_to(IMAGES).parts):
            print(f"REJECTED {src.name}: hidden files aren't published")
            src.unlink()
            rejected.append(src.name)
            continue

        # Not an image at all — a .mov dragged off a camera roll, a stray .txt.
        # It can't be checked for metadata or displayed, so it doesn't belong in
        # a public folder that exists only to be published.
        if src.suffix.lower() not in SOURCES:
            print(f"REJECTED {src.name}: not an image format this page can show")
            src.unlink()
            rejected.append(src.name)
            continue

        if is_clean_webp(src):
            continue

        try:
            body = encode(src)
        except Exception as e:
            # Can't decode it, so can't strip it. Deleting a file you still have
            # a copy of beats publishing coordinates you didn't mean to.
            print(f"REJECTED {src.name}: couldn't read it ({e})")
            src.unlink()
            rejected.append(src.name)
            continue

        was = src.stat().st_size
        src.unlink()  # before free_name, so a .jpg can hand its name to its .webp
        dest = free_name(src.stem, taken)
        dest.write_bytes(body)
        print(f"{src.name} -> {dest.name} "
              f"({was / 1e6:.1f}MB -> {len(body) / 1e6:.1f}MB)")

    # The uploaded folders are empty now that their contents have been re-encoded
    # into the top level. Git doesn't track directories, but the runner's checkout
    # and anyone's working copy would keep them around looking meaningful.
    for d in sorted(IMAGES.rglob("*"), key=lambda p: -len(p.parts)):
        if d.is_dir() and not any(d.iterdir()):
            d.rmdir()

    files = []
    for f in sorted(IMAGES.glob("*.webp")):
        try:
            with Image.open(f) as im:
                files.append([f.name, [im.width, im.height]])
        except Exception as e:
            print(f"couldn't read {f.name}: {e}")
    (ROOT / "image_widths_heights.json").write_text(json.dumps(files))

    total = sum(f.stat().st_size for f in IMAGES.glob("*.webp"))
    print(f"\n{len(files)} images, {total / 1e6:.1f}MB total")

    if rejected:
        REJECTED.write_text("\n".join(rejected))
    return 0


if __name__ == "__main__":
    sys.exit(main())
