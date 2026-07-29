-- 九霄问道 V1.0 FIX4 紧急停用玩家庄
-- 不回滚安全数据结构，仅关闭玩家坐庄并撤销当前庄家；荷老系统庄仍可使用安全RPC。
begin;
update public.casino_settings set player_house_enabled=false where singleton_id=1;
update public.casino_player_house_state
set dealer_character_id=null,is_active=false,deactivated_at=now(),expires_at=null,
    last_reason='V1_FIX4_EMERGENCY_DISABLE',updated_at=now()
where singleton_id=1;
notify pgrst,'reload schema';
commit;
