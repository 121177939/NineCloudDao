-- 从V0.11.10 FIX1紧急安全模式恢复境界原有基础成功率。
begin;
update public.realm_stages rs
set breakthrough_base_rate=b.breakthrough_base_rate
from ncd_release_backup.v01110_fix1_realm_rates b
where b.id=rs.id;
commit;
-- 接着重新执行：202607260530_v01110_fix1_roots_realms_breakthrough.sql
