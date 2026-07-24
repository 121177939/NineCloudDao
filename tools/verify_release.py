#!/usr/bin/env python3
"""Verify NineCloudDao release source or generated archives using stdlib only."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import zipfile
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath


class LocalRefParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.refs: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        for key, value in attrs:
            if key in {"src", "href"} and value:
                if value.startswith(("http://", "https://", "data:", "#", "mailto:")):
                    continue
                self.refs.append(value.split("?", 1)[0].split("#", 1)[0])


class Report:
    def __init__(self) -> None:
        self.passes: list[str] = []
        self.warnings: list[str] = []
        self.errors: list[str] = []

    def ok(self, message: str) -> None:
        self.passes.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)

    def fail(self, message: str) -> None:
        self.errors.append(message)

    def print(self) -> None:
        for item in self.passes:
            print(f"[PASS] {item}")
        for item in self.warnings:
            print(f"[WARN] {item}")
        for item in self.errors:
            print(f"[FAIL] {item}")
        print(f"\n结果：{len(self.passes)} 通过，{len(self.warnings)} 警告，{len(self.errors)} 失败。")

    def markdown(self, title: str) -> str:
        lines = [f"# {title}", "", f"- 通过：{len(self.passes)}", f"- 警告：{len(self.warnings)}", f"- 失败：{len(self.errors)}", ""]
        for heading, items in (("通过项", self.passes), ("警告项", self.warnings), ("失败项", self.errors)):
            lines.extend([f"## {heading}", ""])
            lines.extend([f"- {item}" for item in items] or ["- 无"])
            lines.append("")
        return "\n".join(lines)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_text(path: Path, report: Report) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except Exception as exc:
        report.fail(f"无法读取 {path.name}: {exc}")
        return ""


def check_local_refs(root: Path, report: Report) -> None:
    for html_name in ("index.html", "404.html"):
        parser = LocalRefParser()
        parser.feed(read_text(root / html_name, report))
        missing = []
        for ref in parser.refs:
            if not ref or ref == "./":
                continue
            candidate = root / ref.lstrip("./")
            if not candidate.exists():
                missing.append(ref)
        if missing:
            report.fail(f"{html_name} 引用缺失：{', '.join(sorted(set(missing)))}")
        else:
            report.ok(f"{html_name} 本地资源引用完整")

    try:
        manifest = json.loads((root / "manifest.webmanifest").read_text(encoding="utf-8"))
        missing = [icon.get("src", "") for icon in manifest.get("icons", []) if not (root / icon.get("src", "")).exists()]
        if missing:
            report.fail(f"Manifest 图标缺失：{', '.join(missing)}")
        else:
            report.ok("Manifest 图标资源完整")
    except Exception as exc:
        report.fail(f"manifest.webmanifest 无法解析：{exc}")


def check_node(root: Path, report: Report, require_node: bool) -> None:
    node = shutil.which("node")
    if not node:
        message = "未找到 Node.js，未执行 JavaScript 语法检查"
        if require_node:
            report.fail(message)
        else:
            report.warn(message)
        return
    for name in ("app.js", "config.js", "sw.js"):
        proc = subprocess.run([node, "--check", str(root / name)], capture_output=True, text=True)
        if proc.returncode:
            report.fail(f"{name} JavaScript 语法失败：{(proc.stderr or proc.stdout).strip()}")
        else:
            report.ok(f"{name} JavaScript 语法通过")


def check_sensitive_files(root: Path, candidates: list[str], report: Report) -> None:
    forbidden_names = {".env", ".env.local", ".env.production", "id_rsa", "id_ed25519"}
    discovered = [p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file() and p.name.lower() in forbidden_names]
    if discovered:
        report.fail(f"发现不应发布的敏感文件：{', '.join(discovered)}")
    else:
        report.ok("未发现 .env 或私钥文件名")

    # Patterns are assembled to avoid the verifier matching its own source text.
    secret_token = re.compile("sb_" + "secret_[A-Za-z0-9_-]{8,}")
    private_key = re.compile("-----BEGIN " + "(?:RSA |EC |OPENSSH )?PRIVATE KEY-----")
    credential_uri = re.compile(r"postgres(?:ql)?://[^\s/:]+:[^\s/@]+@", re.I)
    service_value = re.compile(r"service[_-]?role(?:Key)?\s*[:=]\s*['\"][^'\"]{12,}", re.I)
    findings: list[str] = []
    for relative in candidates:
        path = root / relative
        if not path.is_file() or path.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".ico", ".zip"}:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        if secret_token.search(text) or private_key.search(text) or credential_uri.search(text) or service_value.search(text):
            findings.append(relative)
    if findings:
        report.fail(f"发现疑似敏感凭据：{', '.join(sorted(set(findings)))}")
    else:
        report.ok("未发现 Secret key、私钥或带密码的数据库连接串")


def verify_root(root: Path, mode: str, require_node: bool, report: Report) -> dict:
    config_path = root / "release_config.json"
    if not config_path.exists():
        report.fail("缺少 release_config.json")
        return {}
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
        report.ok("release_config.json 可解析")
    except Exception as exc:
        report.fail(f"release_config.json 无法解析：{exc}")
        return {}

    version = str(config.get("version", ""))
    cache_name = str(config.get("serviceWorkerCache", ""))
    github_files = list(config.get("githubFiles", []))
    source_files = list(config.get("sourceOnlyFiles", []))
    if mode == "auto":
        mode = "source" if (root / "database").exists() and (root / "tools/build_release.py").exists() else "github"
    required = github_files + (source_files if mode == "source" else [])

    missing = [item for item in required if not (root / item).is_file()]
    if missing:
        report.fail(f"缺少发布文件：{', '.join(missing)}")
    else:
        report.ok(f"{mode} 模式必需文件完整（{len(required)} 个）")

    if (root / "VERSION.txt").exists() and (root / "VERSION.txt").read_text(encoding="utf-8").strip() == version:
        report.ok("VERSION.txt 与统一版本一致")
    else:
        report.fail("VERSION.txt 与 release_config.json 不一致")

    checks = {
        "config.js": [rf"version:\s*'{re.escape(version)}'"],
        "index.html": [rf'id="versionText">{re.escape(version)}<'],
        "404.html": [rf'id="versionText">{re.escape(version)}<'],
        "sw.js": [re.escape(cache_name)],
        "README.md": [rf"^# 九霄问道 Web Alpha {re.escape(version)}$"],
        "CHANGELOG.md": [rf"^## {re.escape(version)}$"],
        "DESKTOP_UPDATE.md": [rf"^# GitHub Desktop 更新到 V{re.escape(version)}$"],
    }
    for name, patterns in checks.items():
        text = read_text(root / name, report)
        for pattern in patterns:
            if re.search(pattern, text, flags=re.MULTILINE):
                report.ok(f"{name} 当前版本标识正确")
            else:
                report.fail(f"{name} 缺少当前版本标识 {version}")

    if (root / "index.html").exists() and (root / "404.html").exists():
        if (root / "index.html").read_bytes() == (root / "404.html").read_bytes():
            report.ok("index.html 与 404.html 完全一致")
        else:
            report.fail("index.html 与 404.html 内容不一致")

    app = read_text(root / "app.js", report)
    history_expectations = [
        "order: 'world_year.desc,created_at.desc'",
        "limit: '100'",
        '<span class="badge">最新 100 条</span>',
        "const latestRows = (rows || []).slice(0, 100);",
    ]
    if all(item in app for item in history_expectations) and "最早 100 条" not in app and "earliestRows" not in app:
        report.ok("命书按最新 100 条、最新在上实现")
    else:
        report.fail("命书最新 100 条实现不完整或仍残留最早 100 条逻辑")

    sw = read_text(root / "sw.js", report)
    if "url.hostname.endsWith('.supabase.co')" in sw and "return;" in sw:
        report.ok("Service Worker 保持 Supabase 请求不缓存")
    else:
        report.fail("Service Worker 缺少 Supabase 不缓存保护")
    shell_match = re.search(r"const APP_SHELL\s*=\s*\[(.*?)\];", sw, re.S)
    if shell_match:
        shell_refs = re.findall(r"['\"](.+?)['\"]", shell_match.group(1))
        missing_shell = [ref for ref in shell_refs if ref != "./" and not (root / ref.lstrip("./")).exists()]
        if missing_shell:
            report.fail(f"Service Worker APP_SHELL 文件缺失：{', '.join(missing_shell)}")
        else:
            report.ok("Service Worker APP_SHELL 文件完整")
    else:
        report.fail("无法解析 Service Worker APP_SHELL")

    workflow = read_text(root / ".github/workflows/deploy-pages.yml", report)
    verify_pos = workflow.find("tools/verify_release.py")
    upload_pos = workflow.find("actions/upload-pages-artifact")
    if verify_pos >= 0 and upload_pos >= 0 and verify_pos < upload_pos:
        report.ok("GitHub Actions 在上传部署产物前执行自动验证")
    else:
        report.fail("GitHub Actions 未在部署前执行自动验证")

    check_local_refs(root, report)
    check_node(root, report, require_node)
    check_sensitive_files(root, required, report)

    db = config.get("databaseBaseline", {})
    if db.get("publicTables") == 40 and db.get("databaseFunctions") == 23 and db.get("sqlRequired") is False:
        report.ok("数据库基线记录为 40 表、23 函数且本版无需 SQL")
    else:
        report.fail("数据库基线配置不符合 V0.6.6 约束")
    return config


def verify_archive(path: Path, config: dict, report: Report) -> None:
    if not path.exists():
        report.fail(f"归档不存在：{path}")
        return
    try:
        with zipfile.ZipFile(path) as archive:
            corrupt = archive.testzip()
            if corrupt:
                report.fail(f"ZIP 损坏：{path.name}，首个损坏条目 {corrupt}")
                return
            files = [name for name in archive.namelist() if not name.endswith("/")]
            tops = {PurePosixPath(name).parts[0] for name in files if PurePosixPath(name).parts}
            if len(tops) != 1:
                report.fail(f"{path.name} 必须只有一个顶层目录，实际为 {sorted(tops)}")
                return
            top = next(iter(tops))
            expected_top = path.stem
            if top != expected_top:
                report.fail(f"{path.name} 顶层目录应为 {expected_top}，实际为 {top}")
            else:
                report.ok(f"{path.name} 顶层目录正确")
            required = list(config.get("githubFiles", []))
            if "_Game_" in path.name:
                required += list(config.get("sourceOnlyFiles", []))
            missing = [item for item in required if f"{top}/{item}" not in files]
            if missing:
                report.fail(f"{path.name} 缺少文件：{', '.join(missing)}")
            else:
                report.ok(f"{path.name} 文件清单完整（{len(required)} 个）")
            version_text = archive.read(f"{top}/VERSION.txt").decode("utf-8").strip()
            if version_text == str(config.get("version")):
                report.ok(f"{path.name} 内部版本正确")
            else:
                report.fail(f"{path.name} 内部版本错误：{version_text}")
            app = archive.read(f"{top}/app.js").decode("utf-8")
            if "world_year.desc,created_at.desc" in app and "最新 100 条" in app:
                report.ok(f"{path.name} 包含命书最新 100 条修正")
            else:
                report.fail(f"{path.name} 未包含命书最新 100 条修正")
            report.ok(f"{path.name} ZIP 完整性通过，SHA256={sha256(path)}")
    except Exception as exc:
        report.fail(f"无法检查 {path.name}：{exc}")



def compare_archive_runtime(paths: list[Path], config: dict, report: Report) -> None:
    game = next((path for path in paths if "_Game_" in path.name), None)
    github = next((path for path in paths if "_GitHub_Upload_" in path.name), None)
    if not game or not github or not game.exists() or not github.exists():
        return
    try:
        with zipfile.ZipFile(game) as game_zip, zipfile.ZipFile(github) as github_zip:
            game_top = next(iter({PurePosixPath(name).parts[0] for name in game_zip.namelist() if name and not name.endswith("/")}))
            github_top = next(iter({PurePosixPath(name).parts[0] for name in github_zip.namelist() if name and not name.endswith("/")}))
            mismatches = []
            for relative in config.get("githubFiles", []):
                game_bytes = game_zip.read(f"{game_top}/{relative}")
                github_bytes = github_zip.read(f"{github_top}/{relative}")
                if game_bytes != github_bytes:
                    mismatches.append(relative)
            if mismatches:
                report.fail(f"完整游戏包与 GitHub 上传包运行文件不一致：{', '.join(mismatches)}")
            else:
                report.ok(f"完整游戏包与 GitHub 上传包的 {len(config.get('githubFiles', []))} 个发布文件逐字节一致")
    except Exception as exc:
        report.fail(f"无法比较双包运行文件：{exc}")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--mode", choices=["auto", "source", "github"], default="auto")
    parser.add_argument("--require-node", action="store_true")
    parser.add_argument("--archive", type=Path, action="append", default=[])
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    report = Report()
    config = verify_root(args.root.resolve(), args.mode, args.require_node, report)
    resolved_archives = [archive.resolve() for archive in args.archive]
    for archive in resolved_archives:
        verify_archive(archive, config, report)
    compare_archive_runtime(resolved_archives, config, report)
    report.print()
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(report.markdown(f"九霄问道 V{config.get('version', '未知')} 自动验证报告"), encoding="utf-8", newline="\n")
    return 1 if report.errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
