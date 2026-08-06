#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="配置九霄问道 Android 在线更新仓库")
    parser.add_argument("owner", help="GitHub 用户名或组织名")
    parser.add_argument("repo", help="GitHub 仓库名")
    args = parser.parse_args()
    for value, label in ((args.owner, "owner"), (args.repo, "repo")):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", value):
            raise SystemExit(f"{label} 格式不合法：{value}")

    root = Path(__file__).resolve().parents[1]
    path = root / "gradle.properties"
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^GITHUB_OWNER=.*$", f"GITHUB_OWNER={args.owner}", text)
    text = re.sub(r"(?m)^GITHUB_REPO=.*$", f"GITHUB_REPO={args.repo}", text)
    path.write_text(text, encoding="utf-8")
    print(f"已配置更新仓库：https://github.com/{args.owner}/{args.repo}")


if __name__ == "__main__":
    main()
