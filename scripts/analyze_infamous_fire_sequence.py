# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Measure orange fire pixels from existing game-only captures; never edit the captures."""
import argparse
import csv
import json
from pathlib import Path
from PIL import Image, ImageChops


def measure(path):
    with Image.open(path) as image:
        if image.size != (1920, 1080):
            raise ValueError(f"Expected native 1080p screenshot, got {image.size}")
        r, g, b = image.convert("RGB").split()
        mask = ImageChops.multiply(r.point(lambda v: 255 if v >= 180 else 0),
                                  g.point(lambda v: 255 if 30 <= v <= 225 else 0))
        mask = ImageChops.multiply(mask, b.point(lambda v: 255 if v <= 140 else 0))
        mask = ImageChops.multiply(mask, ImageChops.subtract(r, g).point(
            lambda v: 255 if v >= 35 else 0))
        return {name: mask.crop(rect).histogram()[255] for name, rect in {
            "left": (0, 400, 750, 900), "right": (1100, 380, 1920, 950),
            "all": (0, 300, 1920, 950)}.items()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    manifest = args.manifest.resolve(strict=True)
    root = Path(__file__).resolve().parents[1] / "Build" / "particle-benchmark"
    manifest.relative_to(root.resolve())
    with manifest.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    values = []
    for row in rows:
        file = Path(row["File"]).resolve(strict=True)
        file.relative_to(manifest.parent / "screenshots")
        values.append({"index": int(row["Index"]), "seconds": float(row["GameElapsedSeconds"]),
                       "file": str(file), **measure(file)})
    out = manifest.with_name(manifest.stem.replace("-capture", "") + "-fire-metrics.json")
    out.write_text(json.dumps(values, indent=2), encoding="utf-8")
    summary = {key: {"min": min(v[key] for v in values),
                     "max": max(v[key] for v in values)} for key in ("left", "right", "all")}
    print(json.dumps({"frames": len(values), "metrics": str(out), "ranges": summary}))


if __name__ == "__main__":
    main()
