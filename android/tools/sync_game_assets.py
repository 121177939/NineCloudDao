#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import shutil
import tempfile
import zipfile
from pathlib import Path

EXCLUDE_DIRS = {".pages-site", ".github", "tools"}
EXCLUDE_FILES = {".gitignore", ".nojekyll", "README.md", "SHA256SUMS.txt", "404.html", "sw.js", "update-guard.js", "manifest.webmanifest"}

ANDROID_LOCAL_JS = r'''(() => {
  'use strict';
  window.JIUXIAO_ANDROID_LOCAL = Object.freeze({
    localRuntime: true,
    runtime: 'android-apk-assets',
    gameBuild: String(window.GAME_CONFIG?.buildId || 'unknown')
  });
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.getRegistrations()
      .then(registrations => Promise.all(registrations.map(item => item.unregister())))
      .catch(() => undefined);
  }
  document.documentElement.dataset.androidLocal = 'true';
  window.addEventListener('DOMContentLoaded', () => {
    const footer = document.querySelector('.footer');
    if (footer && !footer.querySelector('[data-android-local]')) {
      const label = document.createElement('span');
      label.dataset.androidLocal = 'true';
      label.textContent = 'Android 本地资源版';
      footer.appendChild(label);
    }
  }, { once: true });
})();
'''


def find_public(root: Path) -> Path:
    candidates = [root / "public"] + list(root.rglob("public"))
    for item in candidates:
        if item.is_dir() and (item / "index.html").is_file() and (item / "app.js").is_file():
            return item
    raise FileNotFoundError("资料包中未找到 public/index.html 与 public/app.js")


def main() -> None:
    parser = argparse.ArgumentParser(description="从九霄问道完整部署包同步 APK 内置游戏资源")
    parser.add_argument("source", help="完整部署包 ZIP，或已解压的目录")
    args = parser.parse_args()

    project = Path(__file__).resolve().parents[1]
    target = project / "app/src/main/assets/game"
    source = Path(args.source).expanduser().resolve()
    temp: tempfile.TemporaryDirectory[str] | None = None
    try:
        if source.is_file() and source.suffix.lower() == ".zip":
            temp = tempfile.TemporaryDirectory(prefix="jiuxiao_android_sync_")
            with zipfile.ZipFile(source) as archive:
                for info in archive.infolist():
                    normalized = Path(info.filename)
                    if normalized.is_absolute() or ".." in normalized.parts:
                        raise RuntimeError(f"ZIP包含不安全路径：{info.filename}")
                archive.extractall(temp.name)
            source_root = Path(temp.name)
        elif source.is_dir():
            source_root = source
        else:
            raise FileNotFoundError(source)

        public = find_public(source_root)
        if target.exists(): shutil.rmtree(target)
        target.mkdir(parents=True)
        for src in public.rglob("*"):
            rel = src.relative_to(public)
            if any(part in EXCLUDE_DIRS for part in rel.parts) or src.is_dir() or rel.name in EXCLUDE_FILES:
                continue
            dest = target / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)

        index_path = target / "index.html"
        text = index_path.read_text(encoding="utf-8")
        text = re.sub(r'\s*<link rel="manifest"[^>]*>\s*', '\n', text)
        text = re.sub(r'\s*<script src="update-guard\.js[^>]*></script>\s*', '\n', text)
        config_script = re.search(r'<script src="config\.js[^>]*></script>', text)
        if not config_script:
            raise RuntimeError("index.html 未找到 config.js 引用")
        insertion = config_script.group(0) + '\n  <script src="android-local.js?v=android-local-r1"></script>'
        text = text[:config_script.start()] + insertion + text[config_script.end():]
        index_path.write_text(text, encoding="utf-8")
        (target / "android-local.js").write_text(ANDROID_LOCAL_JS, encoding="utf-8")
        print(f"已同步本地游戏资源：{public} -> {target}")
    finally:
        if temp is not None: temp.cleanup()


if __name__ == "__main__":
    main()
