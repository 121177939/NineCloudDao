// Web A v2.0.51 preview presentation model.
// Only formats the authoritative Kotlin/JS WebParser.inspect() output.
// No payment, sending, cloud mutation, or independent parsing is performed here.
const IGNORED_LABELS=['七星彩','排列五','七五','五七','七星','七子','七仔','五子','五仔','排五','排列','子','七','五']
  .sort((a,b)=>b.length-a.length);

export function normalizeForOffsets(source) {
  let s=String(source).replace(/[ⅩⅹｘＸx*＊ΧχХх]/g,'X')
    .replace(/[－—–﹣]/g,'-').replace(/(?<=[0-9X])一(?=[0-9X])/g,'-')
    .replace(/＝/g,'=').replace(/[\t\u00a0]/g,' ')
    .replace(/[０-９]/g,c=>String.fromCharCode(c.charCodeAt(0)-'０'.charCodeAt(0)+48));
  for(const label of IGNORED_LABELS)s=s.split(label).join(' '.repeat(label.length));
  return s.replace(/\.{2,}/g,m=>','.repeat(m.length))
    .replace(/(?<=[0-9X])\.(?=[0-9X]{4}(?![0-9X]))/g,',')
    .replace(/(?<![0-9X-])([0-9]{4})-(\d{1,3}(?:\.\d+)?)(?=\s|[,，、。；;]|$)/g,'$1=$2');
}

export const moneyJiao=value=>{
  const j=Number(value);
  return Number.isFinite(j)?`${(j/10).toFixed(1).replace(/\.0$/,'')}元`:'金额未知';
};

// Audit-only locator: never re-use a source interval to "prove" two separate items.
// Canonical strings are search hints from the authoritative Kotlin result, not
// a replacement parser or evidence that a source span truly exists.
function locateUnclaimed(raw,normalized,needle,from,occupied) {
  const text=String(needle||'');
  if(!text)return {start:0,end:0,matched:false,source:text};
  for(let at=normalized.indexOf(text,from);at>=0;at=normalized.indexOf(text,at+1)){
    const end=at+text.length;
    if(end>raw.length)continue;
    if(occupied.slice(at,end).some(Boolean))continue;
    // Avoid treating the tail of a longer four-digit number as this item.
    if(/^[0-9X]/.test(text)&&at>0&&/[0-9X]/.test(normalized[at-1]))continue;
    if(/[0-9X]$/.test(text)&&end<normalized.length&&/[0-9X]/.test(normalized[end]))continue;
    occupied.fill(1,at,end);
    return {start:at,end,matched:true,source:raw.slice(at,end)};
  }
  return {start:0,end:0,matched:false,source:text};
}

function ignoredSpans(source) {
  const used=new Uint8Array(source.length),output=[];
  for(const label of IGNORED_LABELS){
    let start=0;
    while(start<source.length){
      const at=source.indexOf(label,start);if(at<0)break;
      const end=at+label.length;
      if(!used.slice(at,end).some(Boolean)){
        used.fill(1,at,end);output.push({start:at,end,source:source.slice(at,end)});
      }
      start=end;
    }
  }
  return output.sort((a,b)=>a.start-b.start);
}

function buildFlags(command, scatterLength){
  const match=String(command||'').match(/(?:^|\|)F=([01]+)(?:\||$)/);
  const flagStr=match?.[1]||'';
  return Array.from({length:scatterLength},(_,i)=>flagStr[i]==='1');
}

// Kotlin SuiteBet canonical positions are a *display hint*, not a second parser.
export function exampleSuite(canonical, limit=30) {
  const pos=['头','百','十','尾'];
  const parts=String(canonical).split('=')[0];
  const fields=pos.map(p=>{
    const match=parts.match(new RegExp(`(?:([0-9]+)|全)${p}`));
    if(!match)return null;
    return match[1]||'0123456789';
  });
  if(fields.every(x=>x===null))return [];
  const output=[];
  function walk(i,text){
    if(output.length>=limit)return;
    if(i===4){output.push(text);return;}
    const digits=fields[i];
    if(!digits){walk(i+1,text+'X');return;}
    for(const digit of digits){walk(i+1,text+digit);if(output.length>=limit)break;}
  }
  walk(0,'');return output;
}

export function createPreviewModel(source, parsed) {
  const raw=String(source), p=parsed||{}, normalized=normalizeForOffsets(raw);
  const issues=Array.isArray(p.issues)?p.issues:[];
  const scatter=Array.isArray(p.scatter)?p.scatter:[];
  const suites=Array.isArray(p.suites)?p.suites:[];
  const flags=buildFlags(p.command,scatter.length);
  const ignored=ignoredSpans(raw), occupied=new Uint8Array(raw.length);
  const warningFor=span=>span.matched?issues.find(x=>x.severity==='WARNING' && span.start<x.end && span.end>x.start):null;

  // Locate suite snippets first so that a later ordinary number cannot be
  // incorrectly highlighted inside a preceding multi-position suite.
  const nextSuiteOffset=new Map();
  const suiteRows=suites.map((suite,i)=>{
    const canonical=String(suite.canonical||''), guessed=String(suite.source||canonical);
    const needle=normalizeForOffsets(guessed.split('=')[0]);
    const from=nextSuiteOffset.get(needle)||0;
    const span=locateUnclaimed(raw,normalized,needle,from,occupied);
    if(span.matched)nextSuiteOffset.set(needle,span.end);
    // Legacy shorthand can compile into a canonical expression not literally
    // present in the input. Show the original for audit, but do NOT claim a
    // verified source offset or silently mark it as Normal.
    if(!span.matched&&suites.length===1&&scatter.length===0)span.source=raw;
    const warning=warningFor(span), examples=exampleSuite(canonical);
    return {...span,index:i,canonical,amountJiao:Number(suite.amountJiao),
      amountText:moneyJiao(suite.amountJiao),expectedCount:Number(suite.expectedCount),
      examples,recognition:canonical.split('=')[0],
      status:!span.matched||warning?'需确认':'正常',
      detail:!span.matched?'预览无法定位该套码在原文中的准确位置，请人工核对':warning?.message||''};
  });

  let cursor=0;
  const allScatter=scatter.map((item,i)=>{
    const span=locateUnclaimed(raw,normalized,String(item.number),cursor,occupied);
    if(span.matched)cursor=span.end;
    const warning=warningFor(span);
    return {...span,number:String(item.number),amountJiao:Number(item.amountJiao),
      amountText:moneyJiao(item.amountJiao),isTurn:flags[i],executionIndex:i+1,
      status:!span.matched||warning?'需确认':'正常',
      detail:!span.matched?'原文中无法定位该散码，请返回核对':warning?.message||''};
  });
  // Android v2.0.21 rule: classification comes from the final number of
  // expanded combinations, not from a Kotlin parser enum or suite syntax.
  // This is display-only: the authoritative p.scatter/p.suites stay unchanged.
  const singlePositionRows=suiteRows.filter(row=>row.expectedCount===1).map(row=>({
    ...row,number:row.examples[0]||row.recognition,isTurn:false,executionIndex:scatter.length+row.index+1
  }));
  const ordinary=[...allScatter.filter(x=>!x.isTurn),...singlePositionRows]
    .sort((a,b)=>(a.matched?a.start:Number.MAX_SAFE_INTEGER)-(b.matched?b.start:Number.MAX_SAFE_INTEGER));
  const turns=allScatter.filter(x=>x.isTurn);
  const multiSuites=suiteRows.filter(x=>x.expectedCount!==1);
  const groups=new Map();
  for(const item of ordinary){
    if(!groups.has(item.amountText))groups.set(item.amountText,[]);
    groups.get(item.amountText).push(item.number);
  }
  const summary=[...groups].map(([amount,codes])=>`${codes.join('、')}各${amount}`).join('；');
  const all=[...ordinary,...turns,...multiSuites];
  return {scatter:ordinary,turns,suites:multiSuites,ignored,errors:issues.filter(x=>x.severity==='ERROR'),
    warnings:issues.filter(x=>x.severity==='WARNING'),scatterOriginal:ordinary.map(s=>s.source).join('，'),
    scatterRecognition:summary,normalCount:all.filter(x=>x.status==='正常').length,
    reviewCount:all.filter(x=>x.status==='需确认').length,
    failCount:issues.filter(x=>x.severity==='ERROR').length,
    totalCount:all.length+issues.filter(x=>x.severity==='ERROR').length,
    scatterCount:ordinary.length,turnCount:turns.length,suiteCount:multiSuites.length};
}
