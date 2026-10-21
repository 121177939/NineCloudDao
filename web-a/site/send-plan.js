/** Frozen command witness: only Kotlin/JS WebParser.inspect + WebParser.plan
 * may issue a command. Preview audit cannot create/send independent commands. */
const ALLOWED=new Set(['arrange','seven','both']);
function fail(msg){throw new Error(msg);}
function int(value){return Number.isSafeInteger(value)&&value>0;}
export function freezeValidatedPlan(parser,input,inspected,preview,suiteScreenshot=false,convertOdds=false){
  if(typeof input!=='string'||!input.trim()||input.length>20000)fail('原文为空或过长');
  const fresh=JSON.parse(parser.inspect(input));
  if(!fresh.valid||!inspected?.valid||fresh.command!==inspected.command ||
     fresh.totalJiao!==inspected.totalJiao||fresh.totalLines!==inspected.totalLines)fail('识别结果已经变化或不一致，必须重新预览');
  if(!int(fresh.totalJiao)||!int(fresh.totalLines))fail('金额或总笔数非法');
  if(!preview||preview.errors.length||preview.failCount||preview.reviewCount||
     !preview.estimatedTotalVerified)fail('识别仍有错误、待确认项或预计金额不能一致核对，拒绝发送');
  const plan=JSON.parse(parser.plan(input,!!suiteScreenshot,!!convertOdds));
  if(!plan.valid||!plan.command||plan.totalJiao!==fresh.totalJiao||
     plan.totalLines!==fresh.totalLines)fail('Kotlin/JS 执行计划验证失败：'+(plan.error||'金额或笔数不同'));
  if(!isWireCommand(plan.command))fail('执行指令不是 Android B 兼容的原始协议');
  // This command remains bound to the exact original input and options;
  // it is not cached as a bearer credential, token or user-controlled copy.
  return Object.freeze({input,command:plan.command,totalJiao:plan.totalJiao,
    totalLines:plan.totalLines,scatterCount:fresh.scatter?.length||0,
    turnCount:fresh.turnCount||0,suiteCount:fresh.suites?.length||0,
    screenshotMode:plan.screenshotMode,convertOdds:!!convertOdds,suiteScreenshot:!!suiteScreenshot});
}
/** M1 for turn/suite/odds; legacy simple scatter for non-M1 native orders. */
export function isWireCommand(command){
  if(typeof command!=='string'||command.length>15000)return false;
  if(command.startsWith('M1|S=')){
    if(!/^M1\|S=[0-9X.;\-]*\|T=[^|]*(?:\|R=[0-9]+)?(?:\|F=[01]+)?(?:\|O=1)?$/.test(command))return false;
    const s=command.slice(5,command.indexOf('|T=')), t=command.slice(command.indexOf('|T=')+3).split('|')[0];
    return s.length>0||t.length>0;
  }
  return /^(?:[0-9X]{4}-(?:\d+(?:\.\d+)?))(?:;[0-9X]{4}-(?:\d+(?:\.\d+)?))*$/.test(command);
}
export function assertSameFrozenPlan(frozen,current){
  const fields=['input','command','totalJiao','totalLines','screenshotMode','suiteScreenshot','convertOdds'];
  if(!frozen||!current||fields.some(k=>frozen[k]!==current[k]))fail('号码或截图/赔率选项变化，请重新确认发送');
  return true;
}
export function planSendSummary(plan,selection){
  if(!ALLOWED.has(selection))fail('未知执行账号');
  const acct=selection==='arrange'?'排列五':selection==='seven'?'七星彩':'排列五＋七星彩';
  const fmt=j=>(j/10).toFixed(1).replace(/\.0$/,'')+'元';
  return `发送账号：${acct}\n任务类型：普通 ${plan.scatterCount-plan.turnCount} · 全转 ${plan.turnCount} · 套码 ${plan.suiteCount}\n单账号预计金额：${fmt(plan.totalJiao)}${selection==='both'?`\n两账号合计：${fmt(plan.totalJiao*2)}`:''}\n执行条目：${plan.totalLines}\n套码截图：${plan.suiteCount?plan.suiteScreenshot?'日志页':'主页统一回图':'不适用'}\n转换倍率：${plan.convertOdds?'开启':'关闭'}`;
}
