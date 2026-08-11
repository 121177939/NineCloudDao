-- 九霄问道 SQL261 · V2.2.0 CACHE133
-- 天道人物真实AI回应修复：自由交谈具体回应 / 冒犯边界 / AI decision 服务端有界映射 / fallback去模板化
-- 基线要求：SQL260 ONLINE / SQL260_GATE_PASSED
-- 成功后：SQL261 ONLINE / NEXT SQL262

begin;

-- ==================== PRECHECK ====================
do $precheck$
begin
  if to_regclass('public.tiandao_people_settings_v259') is null then raise exception 'SQL261_PRECHECK_SQL260_SETTINGS_MISSING'; end if;
  if to_regclass('public.tiandao_life_state_v260') is null then raise exception 'SQL261_PRECHECK_SQL260_LIFE_MISSING'; end if;
  if to_regclass('public.tiandao_story_threads_v260') is null then raise exception 'SQL261_PRECHECK_SQL260_STORY_MISSING'; end if;
  if to_regprocedure('public.tiandao_ai_prepare_v259(uuid,text,uuid,text,text,uuid)') is null then raise exception 'SQL261_PRECHECK_AI_PREPARE_MISSING'; end if;
  if to_regprocedure('public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text)') is null then raise exception 'SQL261_PRECHECK_AI_APPLY_MISSING'; end if;
  if to_regprocedure('public.server_personality_v1(jsonb)') is null then raise exception 'SQL261_PRECHECK_FALLBACK_MISSING'; end if;
  if pg_get_function_result(to_regprocedure('public.tiandao_add_memory_v259(uuid,uuid,text,text,integer,boolean,jsonb)'))<>'void' then raise exception 'SQL261_PRECHECK_MEMORY_ABI_NOT_VOID'; end if;
end
$precheck$;

-- ==================== CONTEXT-AWARE FALLBACK ====================
create or replace function public.server_personality_v1(p_context jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_name text:=coalesce(p_context#>>'{npc,name}','TA');
  v_action text:=coalesce(p_context->>'action','talk');
  v_kind text:=coalesce(p_context->>'request_kind','interaction');
  v_mood text:=coalesce(p_context#>>'{life,mood_label}','');
  v_activity text:=coalesce(p_context#>>'{life,current_activity}','');
  v_place text:=coalesce(p_context#>>'{life,current_place}','');
  v_need text:=coalesce(p_context#>>'{life,current_need}','');
  v_story text:=coalesce(p_context#>>'{active_story,title}','');
  v_player_msg text:=left(trim(coalesce(p_context->>'player_message','')),300);
  v_temper text:=lower(coalesce(p_context#>>'{npc,personality,temperament}','steady'));
  v_affinity integer:=coalesce((p_context#>>'{relation,affinity}')::integer,0);
  v_trust integer:=coalesce((p_context#>>'{relation,trust}')::integer,0);
  v_hostile boolean:=false;
  v_dialogue text;v_goal text;v_intent text;v_reason text;v_decision text:='neutral';
begin
  v_hostile:=v_player_msg ~* '(去你妈|你妈的|尼玛|妈的|傻逼|煞笔|蠢货|废物|滚蛋|滚开|操你|草你|艹你|狗东西|贱人|去死)';
  if v_kind='romance' then
    v_dialogue:=v_name||'认真听完了你的话，没有让这一刻被轻描淡写地带过。';v_goal:='根据真实关系与共同经历判断这份心意';v_intent:='谨慎回应表白';v_reason:='本地人格兜底只提供语言与意图，最终关系由服务端规则审核。';
  elsif v_action like 'talk:free%' or v_action='message:free' then
    if v_hostile then
      v_decision:='reject';
      v_dialogue:=case when v_temper in('fiery','bold','stern') then v_name||'脸色骤然沉了下来：“把话收回去。你若只想来羞辱我，就到此为止。”' when v_temper in('gentle','warm') then v_name||'沉默片刻，神情明显冷了：“我愿意听你说话，不代表我会接受这种羞辱。”' else v_name||'目光冷了下来：“若你只是来羞辱我，就不必再说了。”' end;
      v_goal:='维护自己的边界';v_intent:='拒绝侮辱并拉开距离';v_reason:='玩家原话具有明显侮辱性；本地兜底按NPC人格给出拒绝，不把冒犯包装成正向互动。';
    elsif v_player_msg ~* '(最近|近况|过得|好吗|怎么样)' then
      v_dialogue:=v_name||case when v_mood<>'' then '看了你一眼：“最近么……我今日'||v_mood||'。' else '想了想：“最近还算平稳。' end||case when v_activity<>'' then '手头主要在'||replace(v_activity,'正在','')||'。' else '' end||case when v_story<>'' then '至于“'||v_story||'”那件事，我还没有真正放下。' else '' end||'”';
      v_goal:='把自己的真实近况告诉玩家';v_intent:='具体回应近况询问';v_reason:='根据当日心情、活动与事件直接回应玩家原话。';
    elsif v_player_msg ~* '(怎么看我|觉得我|喜欢我|讨厌我|在意我|关系)' then
      v_dialogue:=v_name||'没有躲开这个问题：“'||case when v_trust>=55 and v_affinity>=35 then '我愿意信你，也已经习惯你出现在我的生活里。只是有些话，我更愿意让往后的事来证明。' when v_trust>=25 or v_affinity>=20 then '我不讨厌和你来往，但我们之间还没有熟到可以把所有话都说死。' else '我们认识得还不够久。我对你有印象，但信任不是几句话就能换来的。' end||'”';
      v_goal:='诚实表达当前关系边界';v_intent:='回应玩家对关系的追问';v_reason:='依据服务端关系画像给出非数值化回答。';
    elsif v_player_msg ~* '(需要|帮你|帮忙|要我做什么)' then
      v_dialogue:=v_name||'略作思索：“'||case when v_story<>'' then '你若真想帮，就先把“'||v_story||'”这件事听明白，别急着替我做决定。' when v_need<>'' then v_need||'。你愿意留下来听听，就已经够了。' else '我眼下没有非要你替我做的事。真有需要，我会开口。' end||'”';
      v_goal:='明确是否需要玩家介入';v_intent:='具体回应帮助意愿';v_reason:='优先使用当前事件与需要，避免空泛套话。';
    elsif v_player_msg ~* '(阵|丹|药|剑|刀|修炼|功法|修行)' then
      v_dialogue:=v_name||'顺着你的话题答道：“'||case when v_activity<>'' then '我现在正'||replace(v_activity,'正在','')||'，所以这件事我确实有些心得。' else '修行上的事，我不会随口给你一个听起来漂亮的答案。' end||'你若想认真聊，就把你卡住的地方说具体些。”';
      v_goal:='围绕修行话题继续具体交流';v_intent:='回应玩家提出的修行话题';v_reason:='用NPC当前活动承接玩家话题。';
    else
      v_dialogue:=v_name||'听完你的原话，没有用一句客套话糊弄过去：“'||case when v_mood='似有心事' then '我今天心里确实压着点事。你既然愿意直接说，我也会直接回你。' when v_mood='有些疲惫' then '我今天有些累，不过你这句话我听进去了。想继续聊，就坐一会。' when v_mood='心情不错' then '今天倒是适合多说几句。你想知道什么，就直问吧。' else '我听见了。你若是真想和我聊，就别只停在一句试探上。' end||'”';
      v_goal:='继续围绕玩家原话交流';v_intent:='给出有当前状态感的直接回应';v_reason:='Cloudflare不可用时仍用当日人物状态回应，而不是固定“我记住了”模板。';
    end if;
  elsif v_action like 'talk:%' then v_dialogue:=v_name||'和你聊了一会。'||case when v_mood<>'' then '今天的TA看起来'||v_mood||'。' else '' end;v_goal:='保持自然来往';v_intent:='继续对话';v_reason:='Cloudflare不可用，使用确定性情境对话兜底。';
  elsif v_action like 'gift:%' then v_dialogue:=v_name||'看了看你准备的东西，没有立刻把心意换算成一句客套话。';v_goal:='按自己的偏好判断这份礼物';v_intent:='对赠礼作出自然反应';v_reason:='礼物效果由服务端偏好规则决定。';
  elsif v_action like 'meeting:%' then v_dialogue:=v_name||'答应和你一起出去走一段。路上没有刻意找话题，却也不显得尴尬。';v_goal:='通过共同经历加深理解';v_intent:='参与相约';v_reason:='相约关系变化由服务端固定规则决定。';
  elsif v_action like 'story:%' then v_dialogue:=v_name||'在“'||coalesce(nullif(v_story,''),'这件事')||'”上听见了你的选择，神情有了一点变化。';v_goal:='继续自己的事件线';v_intent:='根据玩家选择推进个人经历';v_reason:='人生事件推进由服务端阶段规则控制。';
  elsif v_action like 'inbox:%' then v_dialogue:=v_name||'很快看到了你的回应。哪怕只是几句话，也比一直没有回音更真实。';v_goal:='维持主动联系';v_intent:='回应玩家回信';v_reason:='主动来信状态由服务端控制。';
  elsif v_kind='encounter' then v_dialogue:=v_name||'与你在这段缘遇中真正打了照面。';v_goal:='判断这次相识是否值得继续';v_intent:='回应缘遇';v_reason:='缘遇状态由服务端规则处理。';
  elsif v_kind='companion' then v_dialogue:=v_name||'以道侣的身份回应了你。';v_goal:='经营共同生活';v_intent:='回应道侣互动';v_reason:='道侣数值仍由服务端规则处理。';
  else v_dialogue:=v_name||'暂时没有多说什么。';v_goal:='继续自己的修行与人生目标';v_intent:='根据当前关系保持自然往来';v_reason:='Cloudflare不可用，使用确定性的 server_personality_v1。';end if;
  return jsonb_build_object('proposal',jsonb_build_object('decision',v_decision,'dialogue',left(v_dialogue,500),'next_goal',left(v_goal,240),'action_intent',left(v_intent,240),'rationale',left(v_reason,360)),'engine','server_personality_v1');
exception when others then
  return jsonb_build_object('proposal',jsonb_build_object('decision','neutral','dialogue',v_name||'没有敷衍你，只是暂时没把话继续说下去。','next_goal','继续当前目标','action_intent','保持谨慎','rationale','本地人格兜底异常后的最小安全响应'),'engine','server_personality_v1');
end $$;

-- ==================== AI APPLY / SERVER-AUTHORITATIVE FREE TALK ====================
create or replace function public.tiandao_ai_apply_v259(
  p_user_id uuid,p_request_id uuid,p_proposal jsonb,p_engine text,p_model text,p_latency_ms integer default 0,p_failure_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  q public.tiandao_ai_requests_v259%rowtype;s public.tiandao_people_settings_v259%rowtype;n public.tiandao_npcs_v259%rowtype;r public.tiandao_relations_v259%rowtype;e public.tiandao_encounters_v259%rowtype;c public.tiandao_companions_v259%rowtype;t public.tiandao_story_threads_v260%rowtype;i public.tiandao_inbox_v260%rowtype;p public.tiandao_promises_v260%rowtype;
  v_last timestamptz;v_cd int;v_existing uuid;v_player text:='某位修士';v_decision text;v_ai_decision text;v_content text;v_reason text;v_next_goal text;v_intent text;v_family text;v_sub text;v_ref uuid;
  v_score numeric;v_threshold numeric;v_jitter int;da int:=0;dg int:=0;dt int:=0;di int:=0;dr int:=0;dres int:=0;v_cost bigint:=0;v_stage text;v_applied jsonb;v_pref text;v_match boolean:=false;v_story_resolved boolean:=false;v_gift_accepted boolean:=true;v_hostile boolean:=false;
begin
  if p_user_id is null or p_request_id is null then raise exception 'AUTH_REQUIRED';end if;
  select * into q from public.tiandao_ai_requests_v259 where request_id=p_request_id for update;
  if q.request_id is null or q.user_id<>p_user_id then raise exception 'TIANDAO_AI_REQUEST_NOT_FOUND';end if;if q.status<>'prepared' then raise exception 'TIANDAO_AI_REQUEST_ALREADY_APPLIED';end if;if q.expires_at<=clock_timestamp() then update public.tiandao_ai_requests_v259 set status='expired' where request_id=q.request_id;raise exception 'TIANDAO_AI_REQUEST_EXPIRED';end if;
  select * into s from public.tiandao_people_settings_v259 where singleton_id=1;
  select * into n from public.tiandao_npcs_v259 where id=q.npc_id and enabled;if n.id is null then raise exception 'TIANDAO_NPC_NOT_FOUND';end if;
  select * into r from public.tiandao_relations_v259 where character_id=q.character_id and npc_id=n.id for update;if r.npc_id is null then raise exception 'TIANDAO_PERSON_NOT_KNOWN';end if;
  v_ai_decision:=lower(coalesce(p_proposal->>'decision','neutral'));if v_ai_decision not in('accept','defer','reject','neutral') then v_ai_decision:='neutral';end if;
  v_content:=left(trim(coalesce(p_proposal->>'dialogue','')),500);v_reason:=left(trim(coalesce(p_proposal->>'rationale','')),360);v_next_goal:=left(trim(coalesce(p_proposal->>'next_goal','')),240);v_intent:=left(trim(coalesce(p_proposal->>'action_intent','')),240);v_family:=split_part(q.action_code,':',1);v_sub:=split_part(q.action_code,':',2);

  if q.request_kind='interaction' then
    if not s.enabled or not s.interactions_enabled then raise exception 'TIANDAO_INTERACTIONS_DISABLED';end if;
    if v_family in('talk','gift','meeting') then
      select max(created_at) into v_last from public.tiandao_interaction_log_v259 where character_id=q.character_id and npc_id=n.id and (action_code=v_family or action_code like v_family||':%' or action_code like 'companion_'||v_family||'%');
      v_cd:=case v_family when 'talk' then s.talk_cooldown_seconds when 'gift' then s.gift_cooldown_seconds else s.meeting_cooldown_seconds end;if v_last is not null and v_last+make_interval(secs=>v_cd)>clock_timestamp() then raise exception 'TIANDAO_INTERACTION_COOLDOWN';end if;
    end if;

    if v_family='talk' then
      if q.action_code='talk:ask_current' then da:=2;dt:=2;di:=1;
      elsif q.action_code='talk:listen' then da:=2;dt:=3;di:=2;
      elsif q.action_code='talk:share_story' then da:=3;dt:=2;di:=2;
      elsif q.action_code='talk:tease' then da:=case when coalesce(n.personality->>'temperament','steady') in('stern','reserved','cool') then 1 else 3 end;dt:=1;di:=case when r.interaction_count>=3 then 1 else 0 end;
      elsif q.action_code='talk:seek_advice' then da:=1;dt:=2;dres:=3;
      elsif q.action_code='talk:free' then
        if not s.free_talk_enabled or length(q.player_message)<1 then raise exception 'TIANDAO_FREE_TALK_INVALID';end if;
        v_hostile:=q.player_message ~* '(去你妈|你妈的|尼玛|妈的|傻逼|煞笔|蠢货|废物|滚蛋|滚开|操你|草你|艹你|狗东西|贱人|去死)';
        if v_hostile then
          da:=-6;dt:=-5;di:=-1;dres:=-4;v_ai_decision:='reject';
        elsif v_ai_decision='reject' then
          da:=-3;dt:=-2;dres:=-2;
        elsif v_ai_decision='defer' then
          da:=0;dt:=0;di:=0;dres:=0;
        elsif v_ai_decision='accept' then
          da:=2;dt:=2;di:=case when r.trust>=30 then 1 else 0 end;dres:=1;
        else
          da:=1;dt:=1;di:=case when r.trust>=45 then 1 else 0 end;
        end if;
      else raise exception 'TIANDAO_INTERACTION_ACTION_INVALID';end if;
      if v_content='' then v_content:=coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),n.name||'与你聊了一会。');end if;
      perform public.tiandao_add_memory_v259(q.character_id,n.id,q.action_code,v_content,case when q.action_code='talk:free' and length(q.player_message)>=20 then 2 else 1 end,true,jsonb_build_object('player_message',case when q.action_code='talk:free' then q.player_message else null end,'ai_engine',p_engine));

    elsif v_family='gift' then
      v_pref:=public.tiandao_gift_category_v260(n.personality->>'gift_preference');
      if v_pref='none' then v_gift_accepted:=false;v_cost:=0;dres:=1;
      else
        v_cost:=case q.action_code when 'gift:practical' then greatest(200,s.gift_spirit_stone_cost*6/10) when 'gift:cultivation' then greatest(500,s.gift_spirit_stone_cost) when 'gift:elegant' then greatest(800,s.gift_spirit_stone_cost*2) when 'gift:rare' then greatest(1500,s.gift_spirit_stone_cost*5) else 0 end;
        if v_cost>0 then perform public.tianxu_inventory_adjust_v255(q.character_id,'spirit_stone',-v_cost);end if;
        v_match=(v_pref=v_sub);
        da:=case when v_match then 6 when q.action_code='gift:rare' and v_pref<>'rare' then 2 else 3 end;dg:=case when v_match then 5 else 2 end;dt:=case when v_match then 2 else 0 end;dres:=case when v_match then 2 else 0 end;dr:=case when n.romanceable and v_match then 2 when n.romanceable then 0 else 0 end;
      end if;
      if v_content='' then v_content:=case when not v_gift_accepted then n.name||'没有收下礼物，只说彼此相处不必靠这个。' when v_match then n.name||'明显看出了你是认真挑过的，收下时比平时多说了几句。' else n.name||'收下了你的心意，但这并不是TA最偏爱的那一类。' end;end if;
      perform public.tiandao_add_memory_v259(q.character_id,n.id,q.action_code,v_content,2,true,jsonb_build_object('gift_category',v_sub,'preference_match',v_match,'accepted',v_gift_accepted,'spirit_stone_cost',v_cost,'ai_engine',p_engine));

    elsif v_family='meeting' then
      v_match:=case
        when q.action_code='meeting:market' and coalesce(n.personality->>'temperament','') in('shrewd','bright') then true
        when q.action_code='meeting:teahouse' and coalesce(n.personality->>'temperament','') in('calm','gentle','warm','quiet','reserved') then true
        when q.action_code='meeting:mountain' and coalesce(n.personality->>'temperament','') in('free','mysterious','bright') then true
        when q.action_code='meeting:practice' and coalesce(n.personality->>'temperament','') in('focused','stern','bold','fiery','rational') then true
        when q.action_code='meeting:travel' and coalesce(n.personality->>'value_anchor','') in('freedom','adventure','journey','wonder') then true else false end;
      da:=3+case when v_match then 2 else 0 end;dt:=2+case when v_match then 1 else 0 end;di:=3+case when v_match then 2 else 0 end;dr:=case when n.romanceable then 2+case when v_match then 1 else 0 end else 0 end;dres:=case when v_match then 1 else 0 end;
      if v_content='' then v_content:=coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),n.name||'和你一起走了一段。');end if;
      perform public.tiandao_add_memory_v259(q.character_id,n.id,q.action_code,v_content,3,true,jsonb_build_object('meeting',v_sub,'preference_match',v_match,'ai_engine',p_engine));

    elsif v_family='story' then
      begin v_ref:=q.player_message::uuid;exception when others then raise exception 'TIANDAO_STORY_REF_INVALID';end;
      select * into t from public.tiandao_story_threads_v260 where id=v_ref and character_id=q.character_id and npc_id=n.id and status='active' for update;if t.id is null then raise exception 'TIANDAO_STORY_NOT_FOUND';end if;if not exists(select 1 from jsonb_array_elements(t.choices) c0 where c0->>'code'=q.action_code) then raise exception 'TIANDAO_STORY_CHOICE_INVALID';end if;
      if t.stage=1 then
        if q.action_code='story:offer_help' then dt:=2;di:=1;dres:=3;t.branch:='promised';insert into public.tiandao_promises_v260(character_id,npc_id,thread_id,promise_code,title,due_at) values(q.character_id,n.id,t.id,'story_help','答应帮'||n.name||'处理“'||t.title||'”',clock_timestamp()+make_interval(hours=>s.promise_hours)) on conflict do nothing;
        elsif q.action_code='story:listen' then dt:=3;di:=2;dres:=1;t.branch:='trusted';
        else dres:=3;t.branch:='space';end if;t.stage:=2;
      elsif t.stage=2 and t.branch='promised' then
        select * into p from public.tiandao_promises_v260 where character_id=q.character_id and thread_id=t.id and status='active' order by created_at desc limit 1 for update;
        if q.action_code='story:fulfill' then if p.id is not null then update public.tiandao_promises_v260 set status='fulfilled',resolved_at=clock_timestamp() where id=p.id;end if;dt:=5;dg:=3;di:=2;dres:=5;update public.tiandao_relations_v259 set promise_kept=promise_kept+1 where character_id=q.character_id and npc_id=n.id;
        elsif q.action_code='story:be_honest' then if p.id is not null then update public.tiandao_promises_v260 set status='cancelled',resolved_at=clock_timestamp() where id=p.id;end if;dt:=2;dres:=2;
        else if p.id is not null then update public.tiandao_promises_v260 set status='broken',resolved_at=clock_timestamp() where id=p.id;end if;da:=-2;dt:=-4;dres:=-6;update public.tiandao_relations_v259 set promise_broken=promise_broken+1 where character_id=q.character_id and npc_id=n.id;end if;t.stage:=3;
      elsif t.stage=2 then
        if q.action_code='story:ask_progress' then dt:=2;di:=2;elsif q.action_code='story:encourage' then da:=2;dt:=2;dres:=2;else dres:=1;end if;t.stage:=3;
      elsif t.stage=3 then
        if q.action_code='story:stand_with' then da:=2;dt:=4;di:=3;dres:=3;elsif q.action_code='story:advise' then dt:=2;dres:=4;else dt:=3;dres:=4;end if;t.stage:=4;
      elsif t.stage=4 then
        if q.action_code='story:celebrate' then da:=4;di:=4;dr:=case when n.romanceable then 2 else 0 end;
        elsif q.action_code='story:remember' then dt:=4;di:=3;dres:=2;else dres:=2;end if;t.stage:=5;v_story_resolved:=true;
      else raise exception 'TIANDAO_STORY_CHOICE_INVALID';end if;
      if v_content='' then v_content:=coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),n.name||'把你的选择记在了这段经历里。');end if;
      if v_story_resolved then
        update public.tiandao_story_threads_v260 set stage=5,branch=t.branch,current_summary=v_content,choices='[]'::jsonb,status='resolved',last_advanced_at=clock_timestamp(),resolved_at=clock_timestamp() where id=t.id;
        update public.tiandao_life_state_v260 set life_phase=least(99,life_phase+1),updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id;
        perform public.tiandao_add_memory_v259(q.character_id,n.id,'story_resolved','“'||t.title||'”终于走到了结果。'||v_content,5,true,jsonb_build_object('story_id',t.id,'branch',t.branch,'ai_engine',p_engine));
      else
        update public.tiandao_story_threads_v260 set stage=t.stage,branch=t.branch,current_summary=v_content,choices=public.tiandao_story_choices_v260(t.stage,t.branch),last_advanced_at=clock_timestamp(),expires_at=clock_timestamp()+make_interval(hours=>s.story_expire_hours) where id=t.id;
        perform public.tiandao_add_memory_v259(q.character_id,n.id,'story_step','在“'||t.title||'”这件事上，你作出了自己的选择。'||v_content,3,true,jsonb_build_object('story_id',t.id,'stage',t.stage,'branch',t.branch,'ai_engine',p_engine));
      end if;

    elsif v_family='inbox' then
      begin v_ref:=q.player_message::uuid;exception when others then raise exception 'TIANDAO_INBOX_REF_INVALID';end;
      select * into i from public.tiandao_inbox_v260 where id=v_ref and character_id=q.character_id and npc_id=n.id and status in('unread','read') for update;if i.id is null then raise exception 'TIANDAO_INBOX_NOT_FOUND';end if;
      if q.action_code='inbox:reply' then da:=1;dt:=2;di:=1;update public.tiandao_inbox_v260 set status='resolved',read_at=coalesce(read_at,clock_timestamp()),resolved_at=clock_timestamp() where id=i.id;
      elsif q.action_code='inbox:accept' then da:=2;dt:=2;di:=2;update public.tiandao_inbox_v260 set status='resolved',read_at=coalesce(read_at,clock_timestamp()),resolved_at=clock_timestamp() where id=i.id;
      elsif q.action_code='inbox:later' then update public.tiandao_inbox_v260 set status='read',read_at=coalesce(read_at,clock_timestamp()) where id=i.id;
      else raise exception 'TIANDAO_INBOX_ACTION_INVALID';end if;
      if v_content='' then v_content:=coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),n.name||'看到了你的回应。');end if;
      perform public.tiandao_add_memory_v259(q.character_id,n.id,q.action_code,v_content,case when q.action_code='inbox:accept' then 2 else 1 end,true,jsonb_build_object('message_id',i.id,'ai_engine',p_engine));
    else raise exception 'TIANDAO_INTERACTION_ACTION_INVALID';end if;

    update public.tiandao_relations_v259 set
      known_level=case when known_level in('unknown','heard') then 'acquainted' when known_level='acquainted' and interaction_count>=4 then 'familiar' when known_level='familiar' and interaction_count>=12 then 'close' else known_level end,
      affinity=least(100,greatest(-100,affinity+da)),gratitude=least(100,greatest(0,gratitude+dg)),trust=least(100,greatest(0,trust+dt)),intimacy=least(100,greatest(0,intimacy+di)),romance=least(100,greatest(0,romance+dr)),respect=least(100,greatest(0,respect+dres)),interaction_count=interaction_count+1,last_interaction_at=clock_timestamp(),last_action=q.action_code,latest_rumor=v_content,current_status=case when v_family='story' then '你已经卷入TA正在经历的一件事。' when v_family='inbox' then 'TA最近主动联系过你。' else '你们最近仍有来往。' end,updated_at=clock_timestamp()
    where character_id=q.character_id and npc_id=n.id returning * into r;
    insert into public.tiandao_interaction_log_v259(character_id,npc_id,action_code,deltas,content) values(q.character_id,n.id,q.action_code,jsonb_build_object('affinity',da,'gratitude',dg,'trust',dt,'intimacy',di,'romance',dr,'respect',dres,'spirit_stone_cost',v_cost,'gift_accepted',v_gift_accepted,'preference_match',v_match,'story_resolved',v_story_resolved),v_content);
    v_stage:=public.tiandao_relation_stage_v259(r.affinity,r.trust,r.intimacy,r.romance,r.hatred,exists(select 1 from public.tiandao_companions_v259 where character_id=q.character_id and npc_id=n.id and status='active'));
    v_decision:=case when q.action_code='talk:free' then v_ai_decision else 'neutral' end;v_applied:=jsonb_build_object('affinity',da,'gratitude',dg,'trust',dt,'intimacy',di,'romance',dr,'respect',dres,'spirit_stone_cost',v_cost,'relation_stage',v_stage,'gift_accepted',v_gift_accepted,'preference_match',v_match,'story_resolved',v_story_resolved,'hostile_free_talk',v_hostile,'ai_decision',v_ai_decision);

  elsif q.request_kind='encounter' then
    if not s.enabled or not s.encounters_enabled then raise exception 'TIANDAO_ENCOUNTERS_DISABLED';end if;
    select * into e from public.tiandao_encounters_v259 where id=q.encounter_id and character_id=q.character_id for update;if e.id is null then raise exception 'TIANDAO_ENCOUNTER_NOT_FOUND';end if;if e.status<>'pending' then raise exception 'TIANDAO_ENCOUNTER_ALREADY_RESOLVED';end if;if e.expires_at<=clock_timestamp() then raise exception 'TIANDAO_ENCOUNTER_EXPIRED';end if;
    if q.action_code in('approach','accept') then da:=5;dt:=2;di:=1;dres:=1;dr:=case when n.romanceable then 1 else 0 end;elsif q.action_code='observe' then da:=1;dt:=1;dres:=1;elsif q.action_code<>'leave' then raise exception 'TIANDAO_ENCOUNTER_ACTION_INVALID';end if;
    if v_content='' then v_content:=coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),'这段缘遇有了新的结果。');end if;
    update public.tiandao_relations_v259 set known_level=case when q.action_code in('approach','accept') and known_level in('unknown','heard') then 'acquainted' else known_level end,affinity=least(100,greatest(-100,affinity+da)),trust=least(100,greatest(0,trust+dt)),intimacy=least(100,greatest(0,intimacy+di)),romance=least(100,greatest(0,romance+dr)),respect=least(100,greatest(0,respect+dres)),latest_rumor=v_content,current_status=case when q.action_code in('approach','accept') then '你们已经正式相识。' else current_status end,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id returning * into r;
    update public.tiandao_encounters_v259 set status='resolved',resolved_action=q.action_code,outcome=v_content,resolved_at=clock_timestamp() where id=e.id;
    if q.action_code in('approach','accept') then perform public.tiandao_add_memory_v259(q.character_id,n.id,'encounter',v_content,3,true,jsonb_build_object('encounter_id',e.id,'ai_engine',p_engine,'next_goal',v_next_goal,'action_intent',v_intent));end if;
    perform public.tiandao_refresh_person_life_v260(q.character_id,n.id);perform public.tiandao_spawn_story_v260(q.character_id,n.id,false);
    v_decision:='neutral';v_stage:=public.tiandao_relation_stage_v259(r.affinity,r.trust,r.intimacy,r.romance,r.hatred,false);v_applied:=jsonb_build_object('affinity',da,'trust',dt,'intimacy',di,'romance',dr,'respect',dres,'relation_stage',v_stage);

  elsif q.request_kind='romance' then
    if not s.enabled or not s.romance_enabled then raise exception 'TIANDAO_ROMANCE_DISABLED';end if;if q.action_code<>'confess' or length(q.player_message)<1 then raise exception 'TIANDAO_ROMANCE_ACTION_INVALID';end if;if not n.romanceable or r.known_level not in('acquainted','familiar','close') then raise exception 'TIANDAO_ROMANCE_NPC_INVALID';end if;
    if r.affinity<s.confess_affinity_min or r.trust<s.confess_trust_min or r.intimacy<s.confess_intimacy_min or r.romance<s.confess_romance_min or r.hatred>=25 then raise exception 'TIANDAO_CONFESSION_REQUIREMENTS';end if;
    select npc_id into v_existing from public.tiandao_companions_v259 where character_id=q.character_id and status='active';if v_existing is not null and v_existing<>n.id then raise exception 'TIANDAO_COMPANION_ALREADY_EXISTS';elsif v_existing=n.id then raise exception 'TIANDAO_COMPANION_ALREADY_EXISTS';end if;
    select max(created_at) into v_last from public.tiandao_interaction_log_v259 where character_id=q.character_id and npc_id=n.id and action_code='confess';if v_last is not null and v_last+make_interval(secs=>s.confess_cooldown_seconds)>clock_timestamp() then raise exception 'TIANDAO_CONFESSION_COOLDOWN';end if;
    v_jitter:=(mod(mod(hashtextextended(q.character_id::text||':'||n.id::text||':'||date_trunc('hour',clock_timestamp())::text,260),11)+11,11)::int)-5;
    v_score:=r.affinity*0.30+r.trust*0.28+r.intimacy*0.22+r.romance*0.30+r.gratitude*0.07+r.respect*0.08-r.hatred*0.55-r.fear*0.15+coalesce((n.personality->>'romance_openness')::numeric,50)*0.10+least(8,r.promise_kept*2)-least(10,r.promise_broken*3)+v_jitter;v_threshold:=n.romance_threshold;
    if v_score<v_threshold-10 then v_decision:='reject';elsif v_score<v_threshold and v_ai_decision='accept' then v_decision:='defer';elsif v_ai_decision in('accept','defer','reject') then v_decision:=v_ai_decision;elsif v_score>=v_threshold then v_decision:='defer';else v_decision:='reject';end if;
    if v_reason='' then v_reason:=case v_decision when 'accept' then 'AI提出接受，且通过服务端关系、守诺与分数规则审核。' when 'defer' then 'AI或服务端审核判断仍需更多共同经历。' else 'AI或服务端审核判断当前不接受。' end;end if;
    insert into public.tiandao_interaction_log_v259(character_id,npc_id,action_code,deltas,content) values(q.character_id,n.id,'confess',jsonb_build_object('score',v_score,'threshold',v_threshold,'ai_decision',v_ai_decision,'server_decision',v_decision),q.player_message);
    if v_decision='accept' then
      insert into public.tiandao_companions_v259(character_id,npc_id,status) values(q.character_id,n.id,'active') on conflict(character_id) do update set npc_id=excluded.npc_id,status='active',formed_at=clock_timestamp(),updated_at=clock_timestamp();
      if v_content='' then v_content:=n.name||'接受了你的心意。大道漫漫，你们从此以道侣之名同行。';end if;
      update public.tiandao_relations_v259 set known_level='close',affinity=greatest(affinity,80),trust=greatest(trust,70),intimacy=greatest(intimacy,70),romance=greatest(romance,85),respect=greatest(respect,60),current_status='你们已经正式结为道侣。',latest_rumor=v_content,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id;
      perform public.tiandao_add_memory_v259(q.character_id,n.id,'companion_formed',v_content,5,true,jsonb_build_object('message',q.player_message,'ai_engine',p_engine,'next_goal',v_next_goal,'action_intent',v_intent));
      begin select name into v_player from public.player_characters where id=q.character_id;exception when others then v_player:='某位修士';end;perform public.tiandao_publish_world_event_v259('tiandao_companion_v260','仙缘既定',coalesce(nullif(v_player,''),'某位修士')||'与'||n.name||'因缘圆满，正式结为道侣。',3);
    elsif v_decision='defer' then if v_content='' then v_content:=n.name||'没有立刻拒绝，也没有草率答应，希望再多走一段路。';end if;update public.tiandao_relations_v259 set trust=least(100,trust+2),intimacy=least(100,intimacy+1),romance=least(100,romance+1),latest_rumor=v_content,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id;perform public.tiandao_add_memory_v259(q.character_id,n.id,'confession_defer',v_content,4,true,jsonb_build_object('message',q.player_message,'ai_engine',p_engine));
    else if v_content='' then v_content:=n.name||'没有接受这份心意，但也没有让此前经历凭空消失。';end if;update public.tiandao_relations_v259 set romance=greatest(0,romance-5),latest_rumor=v_content,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id;perform public.tiandao_add_memory_v259(q.character_id,n.id,'confession_reject',v_content,4,true,jsonb_build_object('message',q.player_message,'ai_engine',p_engine));end if;
    v_applied:=jsonb_build_object('ai_decision',v_ai_decision,'server_decision',v_decision,'score',v_score,'threshold',v_threshold,'companion_formed',(v_decision='accept'));

  elsif q.request_kind='companion' then
    if not s.enabled or not s.companion_enabled then raise exception 'TIANDAO_COMPANION_DISABLED';end if;select * into c from public.tiandao_companions_v259 where character_id=q.character_id and npc_id=n.id and status='active' for update;if c.character_id is null then raise exception 'TIANDAO_COMPANION_NOT_FOUND';end if;if c.last_action_at is not null and c.last_action_at+make_interval(secs=>s.companion_action_cooldown_seconds)>clock_timestamp() then raise exception 'TIANDAO_COMPANION_ACTION_COOLDOWN';end if;
    if q.action_code in('message','message:free') then
      dt:=2;di:=2;dr:=1;
      if q.action_code='message:free' then
        if not s.free_talk_enabled or length(q.player_message)<1 then raise exception 'TIANDAO_FREE_TALK_INVALID';end if;
        v_hostile:=q.player_message ~* '(去你妈|你妈的|尼玛|妈的|傻逼|煞笔|蠢货|废物|滚蛋|滚开|操你|草你|艹你|狗东西|贱人|去死)';
        if v_hostile then da:=-5;dt:=-6;di:=-2;dr:=-2;dres:=-4;v_ai_decision:='reject';
        elsif v_ai_decision='reject' then da:=-2;dt:=-3;di:=-1;dr:=-1;dres:=-2;
        elsif v_ai_decision='defer' then dt:=0;di:=0;dr:=0;
        elsif v_ai_decision='accept' then da:=1;dt:=2;di:=2;dr:=1;dres:=1;
        else dt:=1;di:=1;dr:=0;end if;
      end if;
    elsif v_family='gift' then
      if q.action_code not in('gift:practical','gift:cultivation','gift:elegant','gift:rare') then raise exception 'TIANDAO_COMPANION_ACTION_INVALID';end if;
      v_pref:=public.tiandao_gift_category_v260(n.personality->>'gift_preference');
      if v_pref='none' then v_gift_accepted:=false;v_cost:=0;dres:=1;
      else
        v_cost:=case q.action_code when 'gift:practical' then greatest(500,s.companion_gift_spirit_stone_cost/5) when 'gift:cultivation' then greatest(1000,s.companion_gift_spirit_stone_cost/2) when 'gift:elegant' then greatest(1500,s.companion_gift_spirit_stone_cost) when 'gift:rare' then greatest(3000,s.companion_gift_spirit_stone_cost*2) else 0 end;
        if v_cost>0 then perform public.tianxu_inventory_adjust_v255(q.character_id,'spirit_stone',-v_cost);end if;
        v_match=(v_pref=v_sub);da:=3+case when v_match then 2 else 0 end;dg:=3;di:=3;dr:=2+case when v_match then 1 else 0 end;dres:=1;
      end if;
    elsif v_family='meeting' then da:=3;dt:=3;di:=5;dr:=3;dres:=2;
    elsif q.action_code='joint_cultivation' then dt:=4;di:=5;dr:=3;dres:=2;
    elsif q.action_code='protect' then dt:=5;di:=3;dr:=2;dres:=4;
    else raise exception 'TIANDAO_COMPANION_ACTION_INVALID';end if;
    if v_content='' then v_content:=case when v_family='gift' and not v_gift_accepted then n.name||'没有收下礼物，只提醒你们之间不需要靠礼物证明什么。' else coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),n.name||'回应了这次道侣互动。') end;end if;
    update public.tiandao_relations_v259 set affinity=least(100,affinity+da),gratitude=least(100,gratitude+dg),trust=least(100,trust+dt),intimacy=least(100,intimacy+di),romance=least(100,romance+dr),respect=least(100,respect+dres),known_level='close',current_status='你们以道侣之名继续各自修行，也彼此牵挂。',latest_rumor=v_content,last_interaction_at=clock_timestamp(),last_action='companion_'||q.action_code,interaction_count=interaction_count+1,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id;
    update public.tiandao_companions_v259 set last_action_at=clock_timestamp(),bond_level=least(10,bond_level+case when v_family='meeting' or q.action_code in('joint_cultivation','protect') then 1 else 0 end),updated_at=clock_timestamp() where character_id=q.character_id;
    insert into public.tiandao_interaction_log_v259(character_id,npc_id,action_code,deltas,content) values(q.character_id,n.id,'companion_'||q.action_code,jsonb_build_object('affinity',da,'gratitude',dg,'trust',dt,'intimacy',di,'romance',dr,'respect',dres,'spirit_stone_cost',v_cost,'gift_accepted',v_gift_accepted,'preference_match',v_match),v_content);
    perform public.tiandao_add_memory_v259(q.character_id,n.id,'companion_'||q.action_code,v_content,case when q.action_code in('joint_cultivation','protect') or v_family='meeting' then 3 else 2 end,true,jsonb_build_object('ai_engine',p_engine,'player_message',case when q.action_code='message:free' then q.player_message else null end,'gift_accepted',v_gift_accepted,'preference_match',v_match));
    v_decision:=case when q.action_code='message:free' then v_ai_decision else 'neutral' end;v_stage:='道侣';v_applied:=jsonb_build_object('affinity',da,'gratitude',dg,'trust',dt,'intimacy',di,'romance',dr,'respect',dres,'spirit_stone_cost',v_cost,'gift_accepted',v_gift_accepted,'preference_match',v_match,'hostile_free_talk',v_hostile,'ai_decision',v_ai_decision);
  else raise exception 'TIANDAO_AI_REQUEST_KIND_INVALID';end if;

  insert into public.tiandao_ai_state_v259(character_id,npc_id,next_goal,action_intent,last_dialogue,last_engine,last_model,updated_at)
  values(q.character_id,n.id,left(coalesce(v_next_goal,''),240),left(coalesce(v_intent,''),240),left(coalesce(v_content,''),500),left(coalesce(p_engine,''),80),left(coalesce(p_model,''),160),clock_timestamp())
  on conflict(character_id,npc_id) do update set next_goal=coalesce(nullif(excluded.next_goal,''),public.tiandao_ai_state_v259.next_goal),action_intent=coalesce(nullif(excluded.action_intent,''),public.tiandao_ai_state_v259.action_intent),last_dialogue=coalesce(nullif(excluded.last_dialogue,''),public.tiandao_ai_state_v259.last_dialogue),last_engine=excluded.last_engine,last_model=excluded.last_model,updated_at=clock_timestamp();
  insert into public.tiandao_ai_decisions_v259(character_id,npc_id,request_id,decision_type,engine,model,decision,score,threshold,rationale,latency_ms,failure_reason,proposal,applied)
  values(q.character_id,n.id,q.request_id,q.request_kind||':'||q.action_code,left(coalesce(nullif(p_engine,''),'server_personality_v1'),80),left(coalesce(nullif(p_model,''),s.ai_model),160),coalesce(v_decision,'neutral'),v_score,v_threshold,left(coalesce(v_reason,''),600),greatest(0,coalesce(p_latency_ms,0)),left(coalesce(p_failure_reason,''),800),coalesce(p_proposal,'{}'::jsonb),coalesce(v_applied,'{}'::jsonb));
  update public.tiandao_ai_requests_v259 set status='applied',applied_at=clock_timestamp() where request_id=q.request_id;
  perform public.tiandao_refresh_person_life_v260(q.character_id,n.id);
  return jsonb_build_object('status','ok','content',v_content,'decision',coalesce(v_decision,'neutral'),'reason',v_reason,'relation_stage',v_stage,'spirit_stone_cost',v_cost,'engine',p_engine,'model',coalesce(nullif(p_model,''),s.ai_model),'ai_latency_ms',greatest(0,coalesce(p_latency_ms,0)),'ai_failure_reason',nullif(left(coalesce(p_failure_reason,''),800),''),'applied',v_applied);
end $$;

-- 内部函数权限保持不向客户端暴露。
revoke all on function public.server_personality_v1(jsonb) from public,anon,authenticated;
revoke all on function public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text) from public,anon,authenticated;
grant execute on function public.server_personality_v1(jsonb) to service_role;
grant execute on function public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text) to service_role;

-- ==================== FINAL GATE ====================
do $gate$
declare v_internal_exposed integer;
begin
  if to_regclass('public.tiandao_life_state_v260') is null or to_regclass('public.tiandao_story_threads_v260') is null then raise exception 'SQL261_GATE_SQL260_TABLE_MISSING'; end if;
  if pg_get_function_result(to_regprocedure('public.server_personality_v1(jsonb)'))<>'jsonb' then raise exception 'SQL261_GATE_FALLBACK_RESULT_CHANGED'; end if;
  if pg_get_function_result(to_regprocedure('public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text)'))<>'jsonb' then raise exception 'SQL261_GATE_APPLY_RESULT_CHANGED'; end if;
  if pg_get_function_result(to_regprocedure('public.tiandao_add_memory_v259(uuid,uuid,text,text,integer,boolean,jsonb)'))<>'void' then raise exception 'SQL261_GATE_MEMORY_ABI_CHANGED'; end if;
  select count(*) into v_internal_exposed from information_schema.routine_privileges where specific_schema='public' and routine_name in('server_personality_v1','tiandao_ai_prepare_v259','tiandao_ai_apply_v259') and grantee in('anon','authenticated','PUBLIC') and privilege_type='EXECUTE';
  if v_internal_exposed<>0 then raise exception 'SQL261_GATE_INTERNAL_RPC_EXPOSED:%',v_internal_exposed;end if;
  if not has_function_privilege('service_role','public.server_personality_v1(jsonb)','EXECUTE') or not has_function_privilege('service_role','public.tiandao_ai_prepare_v259(uuid,text,uuid,text,text,uuid)','EXECUTE') or not has_function_privilege('service_role','public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text)','EXECUTE') then raise exception 'SQL261_GATE_SERVICE_EXECUTE_MISSING';end if;
end
$gate$;

commit;

select jsonb_build_object(
  'sql',261,
  'revision','R1_REAL_AI_RESPONSE',
  'gate','SQL261_GATE_PASSED',
  'release','V2.2.0 CACHE133',
  'module','天道人物自由交谈真实回应 / AI决策有界关系反馈 / 侮辱边界 / context-aware fallback',
  'edge','需要部署 CACHE133 tiandao-ai R2',
  'security','AI仍只提案；关系变化由服务端固定分支审核',
  'next_sql',262
) as sql261_install_result;
