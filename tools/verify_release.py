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

    time_expectations = [
        "rpc/settle_character_time_v1",
        "rpc/reincarnate_character_v1",
        "现实1日=仙历12年",
        "renderDeathScreen",
    ]
    if all(item in app for item in time_expectations):
        report.ok("前端包含仙历、寿元、死亡与轮回流程")
    else:
        report.fail("前端仙历、寿元、死亡或轮回流程不完整")

    technique_expectations = [
        "rpc/get_technique_system_v2",
        "rpc/set_technique_slot_v2",
        "rpc/upgrade_technique_v2",
        "功法 V2",
        "传承点",
        "technique-combination-section",
    ]
    if all(item in app for item in technique_expectations):
        report.ok("前端包含功法 V2 品质、熟练、传承、槽位与组合流程")
    else:
        report.fail("前端功法 V2 流程不完整")

    cave_expectations = [
        "rpc/get_cave_system_v1",
        "rpc/upgrade_cave_building_v1",
        "rpc/start_alchemy_v1",
        "rpc/claim_alchemy_v1",
        "caveSystemRoot",
        "道统洞府",
        "炼丹",
    ]
    if all(item in app for item in cave_expectations):
        report.ok("前端包含道统洞府、建筑升级、挂机资源与炼丹流程")
    else:
        report.fail("前端洞府经营流程不完整")

    ranking_expectations = [
        "rpc/get_destiny_ranking_v1",
        "destinyRankingPanelHtml",
        'data-mobile-tab="ranking"',
        "天命榜",
        "本尊",
        "继续观榜",
    ]
    if all(item in app for item in ranking_expectations):
        report.ok("前端包含天命榜、分页展开、手动刷新与本尊标记")
    else:
        report.fail("前端天命榜流程不完整")

    npc_expectations = [
        "rpc/get_npc_social_v1",
        "rpc/interact_with_npc_v1",
        "rpc/form_npc_relationship_v1",
        "npcSocialPanelHtml",
        'data-mobile-tab="social"',
        "红尘录",
        "义结金兰",
    ]
    if all(item in app for item in npc_expectations):
        report.ok("前端包含红尘录、NPC交游与特殊关系流程")
    else:
        report.fail("前端NPC关系流程不完整")

    sect_expectations = [
        "rpc/get_sect_system_v1",
        "rpc/join_sect_v1",
        "rpc/create_sect_v1",
        "rpc/complete_sect_task_v1",
        "rpc/claim_sect_stipend_v1",
        "rpc/upgrade_sect_building_v1",
        "sectSystemPanelHtml",
        'data-mobile-tab="sect"',
        "宗门",
        "开山立派",
    ]
    if all(item in app for item in sect_expectations):
        report.ok("前端包含宗门列表、建宗入门、事务、俸禄与共享建筑流程")
    else:
        report.fail("前端宗门体系流程不完整")

    opportunity_ui_expectations = [
        'id="opportunityEntryBtn"',
        'opportunityEntryContentHtml',
        'openOpportunityModal',
        '新机缘已自动获取',
        '<div class="aura-inner">机</div>',
    ]
    if all(item in app for item in opportunity_ui_expectations) and 'data-mobile-tab="opportunity"' not in app:
        report.ok("V0.11.2 已将机缘并入修炼页并取消独立底部入口")
    else:
        report.fail("V0.11.2 机缘入口调整不完整")

    if mode == "source":
        time_migration_path = root / "database/V0.7.0/202607240013_time_lifespan_reincarnation.sql"
        time_migration = read_text(time_migration_path, report)
        time_expectations_sql = [
            "game_years_per_real_day numeric(12, 4) not null default 12.0000",
            "create or replace function public.get_game_time_v1()",
            "create or replace function public.settle_character_time_v1()",
            "create or replace function public.reincarnate_character_v1(",
            "create table if not exists public.reincarnation_transitions",
        ]
        if all(item in time_migration for item in time_expectations_sql):
            report.ok("V0.7.0 数据库迁移仍包含 12年/日、寿尽与轮回")
        else:
            report.fail("V0.7.0 数据库迁移内容不完整")

        technique_migration_path = root / "database/V0.8.0/202607240014_technique_system_v2.sql"
        technique_migration = read_text(technique_migration_path, report)
        technique_sql_expectations = [
            "create table if not exists public.technique_system_settings",
            "create table if not exists public.technique_grade_rules",
            "create table if not exists public.technique_combinations",
            "create table if not exists public.character_technique_combo_states",
            "create unique index if not exists character_techniques_equipped_slot_unique",
            "create or replace function public.settle_technique_training_v2()",
            "create or replace function public.set_technique_slot_v2(",
            "create or replace function public.upgrade_technique_v2(",
            "create or replace function public.get_technique_system_v2()",
            "duplicate_technique_effect_replaced_by_mastery",
            "commit;",
        ]
        if all(item in technique_migration for item in technique_sql_expectations):
            report.ok("V0.8.0 数据库迁移包含功法品质、熟练、传承、槽位与组合")
        else:
            report.fail("V0.8.0 数据库迁移内容不完整")

        fixed_expectations = [
            "do $v080_slot_migration$",
            "create temporary table v080_legacy_equipped on commit drop as",
            "join v080_legacy_equipped le on le.id = ct.id",
            "$v080_slot_migration$;",
        ]
        if all(item in technique_migration for item in fixed_expectations):
            report.ok("V0.8.0 已采用 v080_legacy_equipped 作用域修正版")
        else:
            report.fail("V0.8.0 仍可能包含 v080_legacy_equipped 作用域缺陷")

        lower_technique = technique_migration.lower()
        dangerous_technique = lower_technique.replace("drop table if exists v080_legacy_equipped;", "")
        if lower_technique.lstrip().startswith("--") and "begin;" in lower_technique and "commit;" in lower_technique and "drop table" not in dangerous_technique:
            report.ok("V0.8.0 迁移使用事务，且仅清理本次临时表")
        else:
            report.fail("V0.8.0 迁移事务或数据安全检查失败")

        cave_migration_path = root / "database/V0.9.0/202607240015_cave_management.sql"
        cave_migration = read_text(cave_migration_path, report)
        cave_sql_expectations = [
            "raise exception 'V080_FIXED_REQUIRED'",
            "create table if not exists public.cave_system_settings",
            "create table if not exists public.cave_resource_definitions",
            "create table if not exists public.cave_building_definitions",
            "create table if not exists public.cave_recipe_definitions",
            "create table if not exists public.lineage_caves",
            "create table if not exists public.lineage_cave_resources",
            "create table if not exists public.lineage_cave_buildings",
            "create table if not exists public.lineage_alchemy_batches",
            "create or replace function public.initialize_lineage_cave_v1()",
            "create or replace function public.settle_cave_production_v1()",
            "create or replace function public.cave_add_inventory_item_v1(",
            "create or replace function public.get_cave_system_v1()",
            "create or replace function public.upgrade_cave_building_v1(",
            "create or replace function public.start_alchemy_v1(",
            "create or replace function public.claim_alchemy_v1()",
            "offline_cap_hours integer not null default 72",
            "cave_persists_across_reincarnation",
            "commit;",
        ]
        if all(item in cave_migration for item in cave_sql_expectations):
            report.ok("V0.9.0 数据库迁移包含道统洞府、挂机资源、建筑与炼丹")
        else:
            report.fail("V0.9.0 数据库迁移内容不完整")
        lower_cave = cave_migration.lower()
        if lower_cave.lstrip().startswith("--") and "begin;" in lower_cave and "commit;" in lower_cave and "drop table" not in lower_cave and "delete from public.player_characters" not in lower_cave:
            report.ok("V0.9.0 迁移使用事务且未包含删表或删除角色操作")
        else:
            report.fail("V0.9.0 迁移事务或数据安全检查失败")

        cave_check = read_text(root / "database/V0.9.0/202607240015_check.sql", report)
        if all(item in cave_check for item in ("v090_new_table_count", "v090_new_function_count", "output_item_exists", "public_table_count", "public_function_count")):
            report.ok("V0.9.0 提供只读检查SQL并覆盖配方物品绑定与总基线")
        else:
            report.fail("V0.9.0 检查SQL内容不完整")

        ranking_migration = read_text(root / "database/V0.9.1/202607240016_destiny_ranking.sql", report)
        ranking_expectations_sql = [
            "create or replace function public.get_destiny_ranking_v1(",
            "security definer",
            "pc.status in ('active', 'secluded', 'missing')",
            "coalesce(r.major_order, -1) desc",
            "coalesce(rs.minor_level, -1) desc",
            "coalesce(pc.cultivation, 0) desc",
            "grant execute on function public.get_destiny_ranking_v1(integer, integer) to authenticated",
            "revoke all on function public.get_destiny_ranking_v1(integer, integer) from public, anon",
            "commit;",
        ]
        if all(item in ranking_migration.lower() for item in [item.lower() for item in ranking_expectations_sql]):
            report.ok("V0.9.1 数据库迁移包含天命榜排序、认证权限和隐私裁剪RPC")
        else:
            report.fail("V0.9.1 天命榜数据库迁移内容不完整")
        forbidden_ranking_output = ["'email'", "'user_id'", "'character_id'", "'lineage_id'", "'device'"]
        json_section = ranking_migration[ranking_migration.find("'rank', rank_position"):]
        if json_section and not any(item in json_section for item in forbidden_ranking_output):
            report.ok("V0.9.1 天命榜返回对象未包含账号、角色、道统或设备标识")
        else:
            report.fail("V0.9.1 天命榜返回对象可能包含隐私标识")
        if "create table" not in ranking_migration.lower() and "delete from" not in ranking_migration.lower() and "drop table" not in ranking_migration.lower():
            report.ok("V0.9.1 迁移不新增表、不删除玩家数据")
        else:
            report.fail("V0.9.1 迁移包含非预期表或删除操作")

        ranking_check = read_text(root / "database/V0.9.1/202607240016_check.sql", report)
        if all(item in ranking_check for item in ("security_definer", "authenticated_can_execute", "anon_cannot_execute", "expected_function_count", "realm_label")):
            report.ok("V0.9.1 提供只读检查SQL并覆盖权限、基线与榜单预览")
        else:
            report.fail("V0.9.1 检查SQL内容不完整")

        npc_migration = read_text(root / "database/V0.10.0/202607240017_npc_relationships.sql", report)
        npc_sql_expectations = [
            "raise exception 'V091_REQUIRED'",
            "create table if not exists public.npc_social_settings",
            "create table if not exists public.npc_social_archetypes",
            "create table if not exists public.npc_social_characters",
            "create table if not exists public.character_npc_bonds_v1",
            "create table if not exists public.npc_social_events",
            "create or replace function public.initialize_npc_social_v1()",
            "create or replace function public.get_npc_social_v1()",
            "create or replace function public.interact_with_npc_v1(",
            "create or replace function public.form_npc_relationship_v1(",
            "relationship_type = 'master'",
            "relationship_type = 'partner'",
            "gift_spirit_stone_cost",
            "commit;",
        ]
        if all(item.lower() in npc_migration.lower() for item in npc_sql_expectations):
            report.ok("V0.10.0 数据库迁移包含NPC名录、交游、特殊关系与事件")
        else:
            report.fail("V0.10.0 NPC关系数据库迁移内容不完整")
        lower_npc = npc_migration.lower()
        if lower_npc.lstrip().startswith("--") and "begin;" in lower_npc and "commit;" in lower_npc and "drop table" not in lower_npc and "delete from public.player_characters" not in lower_npc:
            report.ok("V0.10.0 迁移使用事务且未包含删表或删除角色操作")
        else:
            report.fail("V0.10.0 迁移事务或数据安全检查失败")
        if "revoke all on function public.refresh_npc_social_effects_v1(uuid) from public, anon, authenticated" in lower_npc:
            report.ok("V0.10.0 内部修炼效果函数未向玩家直接开放")
        else:
            report.fail("V0.10.0 内部NPC效果函数权限可能过宽")

        npc_check = read_text(root / "database/V0.10.0/202607240017_check.sql", report)
        if all(item in npc_check for item in ("v010_new_table_count", "v010_new_function_count", "authenticated_can_execute", "invalid_score_range", "expected_table_count", "expected_function_count")):
            report.ok("V0.10.0 提供只读检查SQL并覆盖结构、权限、异常与最终基线")
        else:
            report.fail("V0.10.0 检查SQL内容不完整")

        sect_migration = read_text(root / "database/V0.11.0/202607240018_sect_system.sql", report)
        sect_sql_expectations = [
            "raise exception 'V010_REQUIRED'",
            "create table if not exists public.sect_system_settings_v1",
            "create table if not exists public.sect_definitions_v1",
            "create table if not exists public.sect_building_definitions_v1",
            "create table if not exists public.sect_task_definitions_v1",
            "create table if not exists public.character_sect_memberships_v1",
            "create table if not exists public.sect_building_states_v1",
            "create table if not exists public.character_sect_daily_tasks_v1",
            "create table if not exists public.sect_events_v1",
            "create or replace function public.get_sect_system_v1()",
            "create or replace function public.join_sect_v1(",
            "create or replace function public.create_sect_v1(",
            "create or replace function public.complete_sect_task_v1(",
            "create or replace function public.claim_sect_stipend_v1()",
            "create or replace function public.upgrade_sect_building_v1(",
            "player_sect_creation_cost integer not null default 5000",
            "commit;",
        ]
        if all(item.lower() in sect_migration.lower() for item in sect_sql_expectations):
            report.ok("V0.11.0 数据库迁移包含宗门、建宗入门、职位贡献、事务、俸禄与建筑")
        else:
            report.fail("V0.11.0 宗门数据库迁移内容不完整")
        lower_sect = sect_migration.lower()
        if lower_sect.lstrip().startswith("--") and "begin;" in lower_sect and "commit;" in lower_sect and "drop table" not in lower_sect and "delete from public.player_characters" not in lower_sect:
            report.ok("V0.11.0 迁移使用事务且未包含删表或删除角色操作")
        else:
            report.fail("V0.11.0 迁移事务或数据安全检查失败")
        if "revoke all on function public.refresh_sect_effects_v1(uuid) from public, anon, authenticated" in lower_sect:
            report.ok("V0.11.0 内部宗门修炼效果函数未向玩家直接开放")
        else:
            report.fail("V0.11.0 内部宗门效果函数权限可能过宽")

        sect_check = read_text(root / "database/V0.11.0/202607240018_check.sql", report)
        if all(item in sect_check for item in ("v011_new_table_count", "v011_new_function_count", "authenticated_can_execute", "duplicate_character_membership", "expected_table_count", "expected_function_count")):
            report.ok("V0.11.0 提供只读检查SQL并覆盖结构、权限、异常与最终基线")
        else:
            report.fail("V0.11.0 检查SQL内容不完整")

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
    expected_tables = db.get("publicTables")
    expected_functions = db.get("databaseFunctions")
    sql_required = db.get("sqlRequired")
    if isinstance(expected_tables, int) and isinstance(expected_functions, int) and isinstance(sql_required, bool):
        report.ok(
            f"数据库基线配置有效：{expected_tables} 表、{expected_functions} 函数，"
            f"{'需要' if sql_required else '不需要'}执行 SQL"
        )
    else:
        report.fail("databaseBaseline 配置缺少合法的表数、函数数或 sqlRequired")
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
                report.ok(f"{path.name} 包含命书最新 100 条规则")
            else:
                report.fail(f"{path.name} 未包含命书最新 100 条规则")
            if "rpc/settle_character_time_v1" in app and "现实1日=仙历12年" in app and "renderDeathScreen" in app:
                report.ok(f"{path.name} 包含 V0.7.0 时间、寿元与轮回前端")
            else:
                report.fail(f"{path.name} 未包含完整的 V0.7.0 时间与轮回前端")
            if all(item in app for item in ("rpc/get_technique_system_v2", "rpc/set_technique_slot_v2", "功法 V2", "传承点")):
                report.ok(f"{path.name} 包含 V0.8.0 功法体系 V2 前端")
            else:
                report.fail(f"{path.name} 未包含完整的 V0.8.0 功法体系 V2 前端")
            if all(item in app for item in ("rpc/get_cave_system_v1", "rpc/upgrade_cave_building_v1", "rpc/start_alchemy_v1", "rpc/claim_alchemy_v1", "道统洞府")):
                report.ok(f"{path.name} 包含 V0.9.0 洞府经营前端")
            else:
                report.fail(f"{path.name} 未包含完整的 V0.9.0 洞府经营前端")
            if all(item in app for item in ("rpc/get_destiny_ranking_v1", "destinyRankingPanelHtml", "天命榜", "继续观榜", "本尊")):
                report.ok(f"{path.name} 包含 V0.9.1 天命榜前端")
            else:
                report.fail(f"{path.name} 未包含完整的 V0.9.1 天命榜前端")
            if all(item in app for item in ("rpc/get_npc_social_v1", "rpc/interact_with_npc_v1", "rpc/form_npc_relationship_v1", "npcSocialPanelHtml", "红尘录", "义结金兰")):
                report.ok(f"{path.name} 包含 V0.10.0 NPC关系前端")
            else:
                report.fail(f"{path.name} 未包含完整的 V0.10.0 NPC关系前端")
            if all(item in app for item in ("rpc/get_sect_system_v1", "rpc/create_sect_v1", "rpc/complete_sect_task_v1", "sectSystemPanelHtml", "开山立派", "领取俸禄")):
                report.ok(f"{path.name} 包含 V0.11.0 宗门体系前端")
            else:
                report.fail(f"{path.name} 未包含完整的 V0.11.0 宗门体系前端")
            if all(item in app for item in ('id="opportunityEntryBtn"', 'openOpportunityModal', '<div class="aura-inner">机</div>')) and 'data-mobile-tab="opportunity"' not in app:
                report.ok(f"{path.name} 包含 V0.11.2 机缘入口调整")
            else:
                report.fail(f"{path.name} 未包含完整的 V0.11.2 机缘入口调整")
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
