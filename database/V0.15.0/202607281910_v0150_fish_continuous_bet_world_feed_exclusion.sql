-- 九霄问道 V0.15.0 主迁移
-- 1. 鱼虾灵局连续点击由前端队列完成，不改赔率、概率或下注表结构。
-- 2. 在九霄界闻的赌坊大堂触发器中明确排除 fish_shrimp，防止今后任何兼容写入被公开播报。

begin;

create or replace function public.world_event_from_house_game_v0140()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cfg boolean := true;
  v_character public.player_characters%rowtype;
  v_world_year integer;
  v_unit text := case when new.stake_type = 'cultivation' then '点修为' else '枚灵石' end;
  v_game_name text := case new.game_code when 'spirit_dice' then '灵骰问道' else '气运龟卜' end;
  v_title text;
  v_content text;
  v_level smallint := 1;
  v_net bigint := greatest(0, coalesce(new.reward_amount, 0) - coalesce(new.stake_amount, 0));
  v_destiny_triple boolean := false;
begin
  -- V0.15.0：鱼虾灵局属于局内连续操作，不进入九霄界闻公开播报。
  if coalesce(new.game_code, '') = 'fish_shrimp' then
    return new;
  end if;

  v_destiny_triple := coalesce((new.result_payload->>'is_destiny_triple')::boolean, false);
  begin
    select s.casino_enabled into v_cfg
    from public.jiuxiao_world_event_settings s
    where s.singleton_id = 1;
    if not coalesce(v_cfg, true) then return new; end if;

    select pc.* into v_character
    from public.player_characters pc
    where pc.id = new.character_id;
    if v_character.id is null then return new; end if;

    select gw.current_year into v_world_year
    from public.game_worlds gw
    where gw.id = v_character.world_id;

    if new.outcome_code = 'win' and v_destiny_triple then
      v_title := '天命豹子';
      v_level := 3;
      v_content := format(
        '紫气贯入万运博弈楼，修士【%s】以%s%s落注“灵骰问道”，竟遇天命豹子，一局净得%s%s。',
        v_character.name, new.stake_amount, v_unit, v_net, v_unit
      );
    elsif new.outcome_code = 'win' then
      v_title := case when v_net >= greatest(100000, new.stake_amount * 10) then '一掷得势' else '赌运亨通' end;
      v_level := case when new.stake_type = 'cultivation' or v_net >= 100000 then 2 else 1 end;
      v_content := format(
        '修士【%s】于万运博弈楼以%s%s落注“%s”，押中天机，一局净得%s%s。',
        v_character.name, new.stake_amount, v_unit, v_game_name, v_net, v_unit
      );
    else
      v_title := case when new.stake_type = 'cultivation' then '修为折损' else '时运不济' end;
      v_level := case when new.stake_type = 'cultivation' or new.stake_amount >= 100000 then 2 else 1 end;
      v_content := format(
        '修士【%s】于万运博弈楼以%s%s落注“%s”，奈何天意难测，一局折损%s%s。',
        v_character.name, new.stake_amount, v_unit, v_game_name, new.stake_amount, v_unit
      );
    end if;

    perform public.world_event_publish_v0140(
      v_character.world_id,
      v_world_year,
      case when v_destiny_triple then 'casino_destiny_triple' else 'casino_house_' || new.outcome_code end,
      v_level,
      v_character.id,
      v_character.name,
      v_title,
      v_content,
      'casino_house_games',
      new.id::text,
      jsonb_build_object(
        'game_code', new.game_code,
        'stake_type', new.stake_type,
        'stake_amount', new.stake_amount,
        'reward_amount', new.reward_amount,
        'net_change', case when new.outcome_code = 'win' then v_net else -new.stake_amount end,
        'is_destiny_triple', v_destiny_triple
      ),
      false,
      null
    );
  exception when others then
    return new;
  end;
  return new;
end;
$$;

revoke all on function public.world_event_from_house_game_v0140() from public, anon, authenticated;

comment on function public.world_event_from_house_game_v0140() is
  'V0.15.0：灵骰问道与气运龟卜继续按原规则进入九霄界闻；fish_shrimp明确排除，不公开播报鱼虾灵局下注与结算。';

update public.jiuxiao_app_release_control
set release_name = 'V0.15.0 CACHE16',
    cache_epoch = greatest(cache_epoch, 16),
    notice_text = '鱼虾灵局已支持连续点击落注，并停止向九霄界闻公开播报鱼虾局内操作。',
    updated_at = now()
where singleton_id = 1;

commit;
