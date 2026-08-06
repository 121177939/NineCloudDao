#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


def read_properties(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        result[key.strip()] = value.strip()
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--notes-file", default="release/release-notes.txt")
    parser.add_argument("--output", default="release-dist/app-update.json")
    parser.add_argument("--apk-name", default="jiuxiao-wendao-release.apk")
    parser.add_argument("--mandatory", action="store_true")
    parser.add_argument("--min-supported-version-code", type=int, default=0)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    props = read_properties(root / "gradle.properties")
    notes_path = root / args.notes_file
    notes = notes_path.read_text(encoding="utf-8").strip() if notes_path.exists() else ""
    payload = {
        "schemaVersion": 1,
        "packageName": props["APP_ID"],
        "versionCode": int(props["APP_VERSION_CODE"]),
        "versionName": props["APP_VERSION_NAME"],
        "apkAssetName": args.apk_name,
        "sha256": args.sha256.lower(),
        "notes": notes,
        "mandatory": bool(args.mandatory),
        "minSupportedVersionCode": int(args.min_supported_version_code),
    }
    output = root / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
