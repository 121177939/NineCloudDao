#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []
WARNINGS: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        ERRORS.append(message)


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def main() -> None:
    required = [
        "settings.gradle.kts", "build.gradle.kts", "gradle.properties",
        "gradlew", "gradlew.bat", "gradle/wrapper/gradle-wrapper.jar",
        "gradle/wrapper/gradle-wrapper.properties", "app/build.gradle.kts",
        "app/src/main/AndroidManifest.xml", "app/src/main/assets/game/index.html",
        "app/src/main/assets/game/app.js", "app/src/main/assets/game/config.js",
        "app/src/main/assets/game/android-local.js",
        "app/src/main/java/com/jiuxiaowendao/game/MainActivity.java",
        "app/src/main/java/com/jiuxiaowendao/game/update/UpdateManager.java",
        "app/src/main/java/com/jiuxiaowendao/game/update/ApkSecurityVerifier.java",
        ".github/workflows/release-apk.yml", "PROJECT_MANIFEST.json",
    ]
    for rel in required:
        check((ROOT / rel).is_file(), f"缺少文件：{rel}")

    # XML structure
    xml_files = list((ROOT / "app/src/main/res").rglob("*.xml")) + [ROOT / "app/src/main/AndroidManifest.xml"]
    for path in xml_files:
        try:
            ET.parse(path)
        except Exception as error:
            ERRORS.append(f"XML解析失败：{path.relative_to(ROOT)}：{error}")

    index = read("app/src/main/assets/game/index.html")
    check("android-local.js" in index, "本地 index 未加载 android-local.js")
    check("update-guard.js" not in index, "本地 index 不应加载 PWA update-guard.js")
    check('rel="manifest"' not in index, "本地 index 不应注册 PWA manifest")

    game_root = ROOT / "app/src/main/assets/game"
    forbidden_runtime = ["sw.js", "update-guard.js", "manifest.webmanifest", "404.html"]
    for name in forbidden_runtime:
        check(not (game_root / name).exists(), f"APK运行资源不应包含：{name}")

    main_java = read("app/src/main/java/com/jiuxiaowendao/game/MainActivity.java")
    client_java = read("app/src/main/java/com/jiuxiaowendao/game/web/LocalGameWebViewClient.java")
    check("appassets.androidplatform.net" in client_java, "未使用 WebViewAssetLoader 本地资源域")
    check('loadUrl("http' not in main_java, "MainActivity 不应直接加载远程网页")
    check("setAllowFileAccess(false)" in main_java, "WebView 未关闭文件访问")
    check("setAllowContentAccess(false)" in main_java, "WebView 未关闭 Content 访问")
    check("setAllowUniversalAccessFromFileURLs(false)" in main_java, "WebView 未关闭 file URL 全局访问")
    check("MIXED_CONTENT_NEVER_ALLOW" in main_java, "WebView 未禁用混合内容")

    manifest = read("app/src/main/AndroidManifest.xml")
    check("REQUEST_INSTALL_PACKAGES" in manifest, "缺少 APK 更新安装权限")
    check('usesCleartextTraffic="false"' in manifest, "未禁用明文流量")
    check("FileProvider" in manifest, "缺少 FileProvider")

    updater = read("app/src/main/java/com/jiuxiaowendao/game/update/ApkSecurityVerifier.java")
    for token in ["sha256", "packageName", "versionCode", "certificateDigests"]:
        check(token in updater, f"APK安全校验缺少：{token}")
    update_manager = read("app/src/main/java/com/jiuxiaowendao/game/update/UpdateManager.java")
    check("checkAutomatically" in update_manager, "缺少自动更新检查入口")
    check("AUTO_CHECK_INTERVAL_MS" in update_manager, "缺少自动更新检查节流")
    check("appMenuButton" not in read("app/src/main/res/layout/activity_main.xml"), "仍存在右下角浮动菜单按钮")
    check("发现新版本" in update_manager and "是否立即更新" in update_manager, "新版本弹窗文案缺失")
    release_workflow = read(".github/workflows/release-apk.yml")
    check("github.repository_owner" in release_workflow, "Release构建未自动注入GitHub owner")
    check("github.event.repository.name" in release_workflow, "Release构建未自动注入GitHub repo")
    github_client = read("app/src/main/java/com/jiuxiaowendao/game/update/GithubReleaseClient.java")
    for token in ["app-update.json", "SHA256SUMS.txt", "schemaVersion", "X-GitHub-Api-Version"]:
        check(token in github_client, f"GitHub更新检查缺少：{token}")

    wrapper_props = read("gradle/wrapper/gradle-wrapper.properties")
    check("gradle-8.2.1-bin.zip" in wrapper_props, "Gradle Wrapper版本不是8.2.1")
    check(re.search(r"distributionSha256Sum=[0-9a-f]{64}", wrapper_props) is not None,
          "Gradle分发包缺少SHA-256校验")

    gradle_props = read("gradle.properties")
    app_gradle = read("app/build.gradle.kts")
    config_js = read("app/src/main/assets/game/config.js")
    check('version "8.2.2"' in read("build.gradle.kts"), "AGP版本不是8.2.2")
    check("compileSdk = 34" in app_gradle, "compileSdk不是34")
    check("targetSdk = 34" in app_gradle, "targetSdk不是34")
    check('androidx.core:core:1.13.1' in app_gradle, "AndroidX Core版本不兼容")
    check('androidx.webkit:webkit:1.11.0' in app_gradle, "AndroidX WebKit版本不兼容")
    baseline = json.loads(read("app/src/main/assets/game/CURRENT_BASELINE.json"))
    check("APP_VERSION_CODE=2000497" in gradle_props, "Android版本号不是CACHE96基线")
    check('APP_VERSION_NAME=2.0.4-cache96-app2' in gradle_props, "Android版本名不是CACHE96基线")
    expected_build = "v2-0-4-cache96-equipment-worldnews3-branchpublish2-appautoupdate1"
    check(expected_build in app_gradle, "BuildConfig游戏构建号不一致")
    check(expected_build in config_js, "config.js游戏构建号不一致")
    check(baseline.get("buildId") == expected_build, "CURRENT_BASELINE游戏构建号不一致")
    check(baseline.get("minimumDatabaseBaseline") == "V2.0.3 CACHE95 / SQL211-221 + SQL229-231 / ADMIN9 R20",
          "数据库最低基线不一致")

    game_files = [p for p in game_root.rglob("*") if p.is_file()]
    check(len(game_files) >= 20, f"游戏资源数量异常：{len(game_files)}")

    forbidden_files = [
        ROOT / "signing.properties", ROOT / "release.keystore", ROOT / "local.properties"
    ]
    for path in forbidden_files:
        check(not path.exists(), f"交付包不应包含本地或签名敏感文件：{path.name}")

    result = {
        "ok": not ERRORS,
        "errors": ERRORS,
        "warnings": WARNINGS,
        "gameFileCount": len(game_files),
        "gameBytes": sum(p.stat().st_size for p in game_files),
        "xmlFileCount": len(xml_files),
        "project": ROOT.name,
        "gameBaseline": "V2.0.4 CACHE96",
        "gameBuildId": expected_build,
        "databaseBaseline": "SQL211-221 + SQL229-231",
        "androidVersionCode": 2000497,
    }
    output = ROOT / "VALIDATION_REPORT.json"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if ERRORS:
        sys.exit(1)


if __name__ == "__main__":
    main()
