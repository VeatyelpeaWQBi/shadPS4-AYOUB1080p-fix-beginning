# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Archive only generated test frames as RGB-lossless video, verifying every pixel first."""
import argparse
import csv
import hashlib
import json
import subprocess
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("manifest", type=Path)
args = parser.parse_args()
manifest = args.manifest.resolve(strict=True)
root = (Path(__file__).resolve().parents[1] / "Build" / "particle-benchmark").resolve()
manifest.relative_to(root)
run = manifest.parent
if run.parent != root or not (run / "scene.json").is_file():
    raise ValueError("Only a prepared project benchmark is allowed")
ffmpeg = Path(r"C:\devtools\ffmpeg\bin\ffmpeg.exe")
if not ffmpeg.is_file():
    raise ValueError("The installed FFmpeg is required; nothing will be downloaded")
with manifest.open(encoding="utf-8-sig", newline="") as stream:
    rows = list(csv.DictReader(stream))
files = [Path(row["File"]).resolve(strict=True) for row in rows]
for file in files:
    if file.parent != run / "screenshots" or not file.name.startswith("CUSA00309_") or file.suffix != ".png":
        raise ValueError("Unexpected capture path")
    with Image.open(file) as image:
        if image.mode != "RGBA" or image.size != (1920, 1080) or image.getextrema()[3] != (255, 255):
            raise ValueError("Only fully opaque native 1080p captures can be archived as RGB")
used = sum(p.stat().st_size for p in root.rglob("*") if p.is_file())
if used + 96 * 2**20 > 1000 * 2**20:
    raise ValueError("Not enough space in the authorized 1 GiB test-data budget")
video = manifest.with_suffix(".mkv")
listing = manifest.with_suffix(".ffconcat")
metadata = manifest.with_suffix(".archive.json")
if metadata.exists() or video.exists() != listing.exists():
    raise ValueError("Archive output already exists")
if any("'" in str(file) for file in files):
    raise ValueError("Unsupported quote in generated capture path")
expected_listing = "".join(f"file '{p.as_posix()}'\nduration 0.5\n" for p in files)
if listing.exists() and listing.read_text(encoding="utf-8") != expected_listing:
    raise ValueError("Existing archive does not refer to this exact sequence")
if not video.exists():
    listing.write_text(expected_listing, encoding="utf-8")
    with manifest.with_suffix(".encode.log").open("wb") as log:
        subprocess.run([str(ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin", "-f", "concat",
                    "-safe", "0", "-i", str(listing), "-fps_mode", "passthrough", "-c:v", "libx264rgb",
                    "-preset", "fast", "-crf", "0", "-threads", "4", "-fs", str(96 * 2**20), str(video)],
                       stdout=log, stderr=log, check=True)
records = []
with manifest.with_suffix(".decode.log").open("wb") as log:
    proc = subprocess.Popen([str(ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin", "-i", str(video),
                             "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"], stdout=subprocess.PIPE, stderr=log)
    try:
        for index, file in enumerate(files):
            chunks, left = [], 1920 * 1080 * 3
            while left:
                block = proc.stdout.read(left)
                if not block:
                    raise ValueError("Truncated archive; original PNGs will be retained")
                chunks.append(block)
                left -= len(block)
            actual = b"".join(chunks)
            with Image.open(file) as image:
                if actual != image.convert("RGB").tobytes():
                    raise ValueError("Archive pixel mismatch; original PNGs will be retained")
            records.append({"index": index, "original_file": str(file),
                            "rgb_sha256": hashlib.sha256(actual).hexdigest()})
        if proc.stdout.read(1) or proc.wait() != 0:
            raise ValueError("Unexpected extra frame or decoder error")
    finally:
        proc.stdout.close()
        if proc.poll() is None:
            proc.kill()
            proc.wait()
# Keep representative PNGs for direct inspection as well as the verified full sequence.
keep = {0, len(files)-1}
metrics = manifest.with_name(manifest.stem.replace("-capture", "") + "-fire-metrics.json")
if metrics.is_file():
    values = json.loads(metrics.read_text(encoding="utf-8"))
    keep.update((min(values, key=lambda v: v["all"])["index"], max(values, key=lambda v: v["all"])["index"]))
metadata.write_text(json.dumps({"video": str(video), "pixel_verified": True, "alpha": 255,
                                "kept_png_indices": sorted(keep), "frames": records}, indent=2), encoding="utf-8")
removed = 0
for index, file in enumerate(files):
    if index not in keep:
        removed += file.stat().st_size
        file.unlink()  # Checked individual files inside this run; original saves are never accessed.
print(json.dumps({"video": str(video), "frames_verified": len(records),
                  "net_saved_mib": round((removed-video.stat().st_size)/2**20, 1)}))
