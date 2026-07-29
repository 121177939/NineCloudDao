-- 九霄问道 V1.0 FIX3：挑战界闻趣味文案
-- 目标：明确“谁挑战谁、谁胜谁负、使用何种兵刃、损失多少修为”，并按战况生成修仙化文案。
-- 安全：只重写 battle_challenge 类型的九霄界闻；异常被触发器隔离，不影响挑战结算。
begin;

do $$
begin
  if to_regclass('public.battle_challenges_bcombat01') is null then
    raise exception 'V1_FIX3_REQUIRED:BATTLE_CHALLENGES_TABLE_MISSING';
  end if;
  if to_regclass('public.world_events') is null then
    raise exception 'V1_FIX3_REQUIRED:WORLD_EVENTS_TABLE_MISSING';
  end if;
end $$;

create or replace function public.bcombat01_world_event_story_fix3(
  p_challenger jsonb,
  p_target jsonb,
  p_winner_id uuid,
  p_rounds integer,
  p_transfer bigint,
  p_result jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare
  v_challenger_name text:=coalesce(nullif(btrim(p_challenger->>'name'),''),'无名修士');
  v_target_name text:=coalesce(nullif(btrim(p_target->>'name'),''),'无名修士');
  v_challenger_weapon text:=coalesce(nullif(btrim(p_challenger->>'weapon_name'),''),'赤手空拳');
  v_target_weapon text:=coalesce(nullif(btrim(p_target->>'weapon_name'),''),'赤手空拳');
  v_challenger_unarmed boolean:=coalesce(nullif(p_challenger->>'is_unarmed','')::boolean,true);
  v_target_unarmed boolean:=coalesce(nullif(p_target->>'is_unarmed','')::boolean,true);
  v_challenger_won boolean:=p_winner_id=(p_challenger->>'character_id')::uuid;
  v_winner_name text;
  v_loser_name text;
  v_winner_weapon text;
  v_winner_unarmed boolean;
  v_opening text;
  v_finisher text;
  v_title text;
  v_content text;
  v_variant integer:=1+floor(random()*5)::integer;
  v_rounds integer:=greatest(1,coalesce(p_rounds,1));
  v_transfer bigint:=greatest(0,coalesce(p_transfer,0));
  v_winner_hp numeric:=0;
  v_winner_max_hp numeric:=1;
  v_close_fight boolean:=false;
  v_element_advantage boolean:=false;
begin
  if v_challenger_won then
    v_winner_name:=v_challenger_name;
    v_loser_name:=v_target_name;
    v_winner_weapon:=v_challenger_weapon;
    v_winner_unarmed:=v_challenger_unarmed;
    v_winner_hp:=greatest(0,coalesce(nullif(p_result->>'challenger_hp_after','')::numeric,0));
    v_winner_max_hp:=greatest(1,coalesce(nullif(p_challenger->>'vitality','')::numeric,1));
  else
    v_winner_name:=v_target_name;
    v_loser_name:=v_challenger_name;
    v_winner_weapon:=v_target_weapon;
    v_winner_unarmed:=v_target_unarmed;
    v_winner_hp:=greatest(0,coalesce(nullif(p_result->>'target_hp_after','')::numeric,0));
    v_winner_max_hp:=greatest(1,coalesce(nullif(p_target->>'vitality','')::numeric,1));
  end if;

  v_close_fight:=v_winner_hp/v_winner_max_hp<=0.25;
  v_element_advantage:=(
    (p_challenger->>'element'='metal' and p_target->>'element'='wood') or
    (p_challenger->>'element'='wood' and p_target->>'element'='earth') or
    (p_challenger->>'element'='earth' and p_target->>'element'='water') or
    (p_challenger->>'element'='water' and p_target->>'element'='fire') or
    (p_challenger->>'element'='fire' and p_target->>'element'='metal')
  )=v_challenger_won;

  v_opening:=case when v_challenger_unarmed
    then format('%s未携兵刃，只以一双肉掌向%s发起挑战',v_challenger_name,v_target_name)
    else format('%s执%s向%s发起挑战',v_challenger_name,v_challenger_weapon,v_target_name)
  end;
  v_finisher:=case when v_winner_unarmed
    then case v_variant when 1 then '掌中真元' when 2 then '一记重掌' when 3 then '拳意' when 4 then '并指剑气' else '护体罡劲' end
    else v_winner_weapon
  end;

  if v_challenger_won then
    if v_rounds<=3 then
      v_title:='摧枯拉朽';
      v_content:=format('%s。%s攻势如雷，不过%s回合便震散%s的护体灵光。%s体力不支，惨败于%s下，被夺走%s点修为。',
        v_opening,v_challenger_name,v_rounds,v_target_name,v_target_name,v_finisher,v_transfer);
    elsif v_close_fight then
      v_title:='险胜半招';
      v_content:=format('%s。双方鏖战%s回合，皆已灵力将尽。%s强提一口真元，以%s抢得最后半招；%s终因体力不支落败，被夺走%s点修为。',
        v_opening,v_rounds,v_challenger_name,v_finisher,v_target_name,v_transfer);
    elsif v_element_advantage then
      v_title:='五行相制';
      v_content:=format('%s。交锋之间五行之势渐显，%s借属性相克催动%s，破去%s周身灵障。%s败下阵来，被夺走%s点修为。',
        v_opening,v_challenger_name,v_finisher,v_target_name,v_target_name,v_transfer);
    elsif v_variant in(1,2) then
      v_title:='越阶破敌';
      v_content:=format('%s。双方斗法%s回合，%s寻得气机破绽，以%s击溃%s护体灵光。%s体力不支，惨败于%s下，被夺走%s点修为。',
        v_opening,v_rounds,v_challenger_name,v_finisher,v_target_name,v_target_name,v_finisher,v_transfer);
    elsif v_variant in(3,4) then
      v_title:='一击定胜';
      v_content:=format('%s。%s久攻不乱，待%s招式露出一线空门，骤然催动%s定下胜负。%s败退之后，被夺走%s点修为。',
        v_opening,v_challenger_name,v_target_name,v_finisher,v_target_name,v_transfer);
    else
      v_title:='天命争锋';
      v_content:=format('%s。两人鏖战%s回合，灵光照彻斗法台。最终%s以%s压过%s一筹，夺得%s点修为，声名传遍九霄。',
        v_opening,v_rounds,v_challenger_name,v_finisher,v_target_name,v_transfer);
    end if;
  else
    if v_rounds<=3 then
      v_title:='越阶未成';
      v_content:=format('%s，却未能撼动%s根基。%s仅用%s回合便以%s震散其攻势；%s挑战失败，惨败于%s下，被夺走%s点修为。',
        v_opening,v_target_name,v_target_name,v_rounds,v_finisher,v_challenger_name,v_finisher,v_transfer);
    elsif v_close_fight then
      v_title:='守榜险胜';
      v_content:=format('%s。双方鏖战%s回合，%s几乎攻破洞天防线，奈何最后一式未能建功。%s强撑伤势，以%s反击定胜；%s挑战失败，被夺走%s点修为。',
        v_opening,v_rounds,v_challenger_name,v_target_name,v_finisher,v_challenger_name,v_transfer);
    elsif v_element_advantage then
      v_title:='五行镇敌';
      v_content:=format('%s。%s借五行之势稳守不退，待%s攻势渐衰，以%s反压灵机。%s挑战失败，败退后被夺走%s点修为。',
        v_opening,v_target_name,v_challenger_name,v_finisher,v_challenger_name,v_transfer);
    elsif v_variant in(1,2) then
      v_title:='守榜退敌';
      v_content:=format('%s。%s沉着应对，任其连攻%s回合而道心不乱，随后以%s反击破敌。%s挑战失败，惨败于%s下，被夺走%s点修为。',
        v_opening,v_target_name,v_rounds,v_finisher,v_challenger_name,v_finisher,v_transfer);
    elsif v_variant in(3,4) then
      v_title:='轻敌折戟';
      v_content:=format('%s，不料%s早已看破其气机。斗至第%s回合，%s骤然催动%s横断攻势；%s体力不支，挑战失败并被夺走%s点修为。',
        v_opening,v_target_name,v_rounds,v_target_name,v_finisher,v_challenger_name,v_transfer);
    else
      v_title:='道途受挫';
      v_content:=format('%s。双方灵力激荡，鏖战%s回合，%s终因后继无力，被%s以%s击溃护体真元。此番挑战未成，%s被夺走%s点修为。',
        v_opening,v_rounds,v_challenger_name,v_target_name,v_finisher,v_challenger_name,v_transfer);
    end if;
  end if;

  return jsonb_build_object(
    'title',v_title,
    'content',v_content,
    'challenger_name',v_challenger_name,
    'target_name',v_target_name,
    'winner_name',v_winner_name,
    'loser_name',v_loser_name,
    'story_revision','V1.0_FIX3'
  );
end
$$;
revoke all on function public.bcombat01_world_event_story_fix3(jsonb,jsonb,uuid,integer,bigint,jsonb) from public,anon,authenticated;

create or replace function public.bcombat01_refresh_world_event_fix3()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare v_story jsonb;
begin
  if new.world_event_id is null then return new;end if;
  begin
    v_story:=public.bcombat01_world_event_story_fix3(
      new.challenger_snapshot,
      new.target_snapshot,
      new.winner_character_id,
      new.battle_rounds,
      new.requested_cultivation_transfer,
      new.result
    );
    update public.world_events
       set title=left(v_story->>'title',80),
           content=left(v_story->>'content',1200),
           metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
             'challenger_id',new.challenger_character_id,
             'target_id',new.target_character_id,
             'winner_id',new.winner_character_id,
             'loser_id',new.loser_character_id,
             'story_revision','V1.0_FIX3'
           )
     where id=new.world_event_id
       and event_type='battle_challenge';
  exception when others then
    -- 九霄界闻文案失败不得影响挑战结算。
    return new;
  end;
  return new;
end
$$;
revoke all on function public.bcombat01_refresh_world_event_fix3() from public,anon,authenticated;

drop trigger if exists trg_bcombat01_refresh_world_event_fix3 on public.battle_challenges_bcombat01;
create trigger trg_bcombat01_refresh_world_event_fix3
after insert or update of world_event_id on public.battle_challenges_bcombat01
for each row
when (new.world_event_id is not null)
execute function public.bcombat01_refresh_world_event_fix3();

-- 让已产生的挑战界闻也切换为新文案；触发器内部故障隔离，不改动战斗结果。
update public.battle_challenges_bcombat01
set world_event_id=world_event_id
where world_event_id is not null;

notify pgrst,'reload schema';
commit;
