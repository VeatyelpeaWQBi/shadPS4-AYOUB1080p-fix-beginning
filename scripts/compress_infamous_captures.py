# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Losslessly re-encode benchmark PNGs, verifying every decoded pixel before replacement."""
import argparse
import json
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("run")
parser.add_argument("--file", type=Path, help="Compress one just-captured frame within this run")
parser.add_argument("--optimize", action="store_true", help="Spend more CPU time on lossless PNG compression")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1] / "Build" / "particle-benchmark"
run = (root / args.run).resolve(strict=True)
run.relative_to(root.resolve())
if run.parent != root.resolve() or not (run / "scene.json").is_file():
    raise ValueError("Only a prepared isolated benchmark run may be compressed")
saved = 0
files = sorted((run / "screenshots").glob("CUSA00309_*_game_*.png"))
if args.file:
    target = args.file.resolve(strict=True)
    if target not in files:
        raise ValueError("Only a native game frame in this prepared run is allowed")
    files = [target]
index = 0
for index, file in enumerate(files, 1):
    temp = file.with_suffix(".lossless.tmp")
    if temp.exists():
        raise ValueError("Unexpected previous compression temporary file")
    with Image.open(file) as original:
        original.load()
        original.save(temp, format="PNG", compress_level=9 if args.optimize else 6,
                      optimize=args.optimize)
        with Image.open(temp) as check:
            if check.mode != original.mode or check.size != original.size or check.tobytes() != original.tobytes():
                raise ValueError(f"Pixel verification failed for {file.name}")
    before, after = file.stat().st_size, temp.stat().st_size
    if after < before:
        temp.replace(file)
        saved += before - after
    else:
        temp.unlink()
    if index % 24 == 0:
        print(json.dumps({"frames": index, "saved_mib": round(saved / 2**20, 1)}), flush=True)
print(json.dumps({"frames": index, "saved_mib": round(saved / 2**20, 1)}))
