-- 九霄问道 V1.0 B-COMBAT01 完整回滚
-- 会删除本模块挑战记录、五行资料、战利修为暂存及装备适配数据。
begin;
update public.fates f
set description=b.description,
    modifiers=b.modifiers,
    trigger_rules=b.trigger_rules
from ncd_b_module_backup.bcombat01_fates b
where f.code=b.code and b.code='sword_heart';
drop table if exists ncd_b_module_backup.bcombat01_fates;

drop trigger if exists trg_bcombat01_assign_element on public.player_characters;
drop function if exists public.challenge_battle_power_bcombat01(uuid,uuid);
drop function if exists public.claim_battle_cultivation_escrow_bcombat01();
drop function if exists public.get_battle_challenge_preview_bcombat01(uuid);
drop function if exists public.get_my_battle_snapshot_v1();
drop function if exists public.get_battle_power_ranking_bcombat01(integer,integer);
drop function if exists public.bcombat01_resolve_hit(jsonb,jsonb,integer,integer,integer);
drop function if exists public.bcombat01_character_snapshot(uuid);
drop function if exists public.bcombat01_character_insert_trigger();
drop function if exists public.bcombat01_assign_element(uuid);
drop function if exists public.bcombat01_element_multiplier(text,text,integer,integer,integer,integer);
drop function if exists public.bcombat01_element_overcomes(text,text);
drop function if exists public.bcombat01_element_label(text);
drop table if exists public.battle_challenges_bcombat01;
drop table if exists public.character_battle_cultivation_escrow_bcombat01;
drop table if exists public.battle_challenge_settings_bcombat01;
drop table if exists public.character_combat_loadouts_bcombat01;
drop table if exists public.character_combat_profiles_bcombat01;
drop table if exists public.combat_realm_stats_bcombat01;
update public.jiuxiao_app_release_control set release_name='V0.15.5 FIX1 CACHE27',cache_epoch=greatest(cache_epoch,31),notice_text='V1.0战斗模块已回滚；请同步部署回滚前端包。',updated_at=now() where singleton_id=1;
notify pgrst,'reload schema';
commit;
