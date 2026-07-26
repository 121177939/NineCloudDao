-- V0.11.10 FIX1 紧急安全模式：临时让突破基础成功率为100%，并清除失败状态。
-- 仅在FIX1已经成功部署后使用。
begin;
update public.realm_stages set breakthrough_base_rate=1.0;
update public.character_breakthrough_states
set failure_count=0,compensation_bonus=0,original_target_stage_id=null,
    affliction_code=null,affliction_name=null,affliction_steps_remaining=0,
    major_fall_used=false,major_fall_origin_stage_id=null,
    last_failure_result=null,updated_at=now();
commit;
notify pgrst,'reload schema';
