#!/usr/bin/env python3
"""Turn the rater log ("rate <key>|<eight scores>" lines, from
HOOPWISE_SHOT=rateLibrary on the Mac demo copy) into
Hoopwise/Models/ActivityLibraryAttributes.swift.

usage: merge.py ratings.txt [more.txt …]   (later files win)
"""
import sys, json, pathlib

ratings = {}
for path in sys.argv[1:]:
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line.startswith("rate ") or line.startswith(("rate missing", "rate error", "rate finished", "rate no key")):
            continue
        key, _, scores = line[5:].rpartition("|")
        values = [int(v) for v in scores.split(",")]
        if len(values) == 8:
            ratings[key] = [max(0, min(3, v)) for v in values]

out = pathlib.Path(__file__).resolve().parents[2] / "Hoopwise/Models/ActivityLibraryAttributes.swift"
lines = [
    "// GENERATED — what each library activity develops, rated by Claude on the",
    "// eight DrillAttribute axes (DrillAttribute.allCases order: ballHandling,",
    "// passing, shooting, finishing, playmaking, gameIQ, defense, footwork),",
    "// 0–3 each. Regenerate with HOOPWISE_SHOT=rateLibrary on the Mac demo copy",
    "// (DrillRater) and tools/attributes/merge.py; don't hand-edit.",
    "enum ActivityLibraryAttributes {",
    "    static let ratings: [String: [Int]] = [",
]
for key in sorted(ratings):
    lines.append(f"        {json.dumps(key, ensure_ascii=False)}: {ratings[key]},")
lines += ["    ]", "}", ""]
out.write_text("\n".join(lines), encoding="utf-8")
print(f"{len(ratings)} ratings → {out}")
