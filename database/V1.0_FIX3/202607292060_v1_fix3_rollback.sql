-- 九霄问道 V1.0 FIX3：界闻趣味文案回滚
-- 仅停止后续挑战界闻重写并删除FIX3私有函数；已生成的历史界闻正文不会自动恢复。
begin;

drop trigger if exists trg_bcombat01_refresh_world_event_fix3 on public.battle_challenges_bcombat01;
drop function if exists public.bcombat01_refresh_world_event_fix3();
drop function if exists public.bcombat01_world_event_story_fix3(jsonb,jsonb,uuid,integer,bigint,jsonb);

notify pgrst,'reload schema';
commit;
