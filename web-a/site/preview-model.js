import {auditFullTurnSource,groupVerifiedSlices,turnPermutationCount} from './fullturn-audit.js';
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

// When Kotlin has accepted whitespace-separated suite position fields, its
// canonical form contains no spaces (e.g. "678头387尾=2"). Audit may match
// only the SAME ordered digit/position tokens, allowing whitespace at the
// token boundaries; never infer digits, punctuation or extra positions.
// Offsets are deliberately indexes into the UNMODIFIED raw input.
function locateSuiteWithWhitespace(raw,normalized,canonical,occupied){
  const needle=String(canonical||'').split('=')[0];
  const tokens=[...needle.matchAll(/([0-9X]+|全)([头百十尾])/g)];
  if(tokens.length<2||tokens.length>4||tokens.map(x=>x[0]).join('')!==needle)
    return {start:0,end:0,matched:false,source:needle};
  const spacer='[ \t\r\n\u00a0]*';
  const pattern=tokens.map(x=>x[1]+spacer+x[2]).join(spacer);
  const regex=new RegExp(pattern,'g');let found;
  while((found=regex.exec(normalized))!==null){
    const at=found.index,end=regex.lastIndex;
    if(end>raw.length||occupied.slice(at,end).some(Boolean))continue;
    if(at>0&&/[0-9X]/.test(normalized[at-1]))continue;
    if(end<normalized.length&&/[0-9X]/.test(normalized[end]))continue;
    const source=raw.slice(at,end);
    // Reject any match whose sole difference is NOT spacing; original text
    // and exact indices are preserved, never reconstructed from canonical.
    if(normalized.slice(at,end).replace(/[ \t\r\n\u00a0]/g,'')!==needle)continue;
    occupied.fill(1,at,end);
    return {start:at,end,matched:true,source};
  }
  return {start:0,end:0,matched:false,source:needle};
}

// Kotlin/JS returns SuiteBet.canonicalText as its preview hint for legacy shorthand
// forms such as "全头16尾", "678—387", "67-57X38" and "2X7-269". Those strings
// are NOT literal substrings of the input. This audit-only mapper builds exact
// source spellings from the authoritative canonical position map, then returns
// offsets into the unchanged input. It never parses a wager or changes the wire plan.
function escapeRegexLiteral(value){
  return String(value).replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
}
function locateSuiteSourceAlias(raw,normalized,canonical,from,occupied){
  const code=String(canonical||'').split('=')[0];
  const tokens=[...code.matchAll(/([0-9]+)([头百十尾])/g)];
  if(tokens.length<2||tokens.length>4||tokens.map(x=>x[0]).join('')!==code)
    return {start:0,end:0,matched:false,source:code};
  const fields=new Map(tokens.map(x=>[x[2],x[1]]));
  const spacer='[ \\t\\r\\n\\u00a0]*';
  const namedPattern=tokens.map(x=>{
    const digits=x[1]==='0123456789'?'(?:0123456789|全)':escapeRegexLiteral(x[1]);
    const label=x[2]==='尾'?'(?:尾|个)':escapeRegexLiteral(x[2]);
    return digits+spacer+label;
  }).join(spacer);
  const patterns=[namedPattern];
  // Legacy numeric dash shorthand: two groups mean head + tail.
  if(fields.size===2&&fields.has('头')&&fields.has('尾'))
    patterns.push(escapeRegexLiteral(fields.get('头'))+'-'+escapeRegexLiteral(fields.get('尾')));
  // Four numeric groups mean head / hundred / ten / tail.
  if(fields.size===4&&['头','百','十','尾'].every(k=>fields.has(k)))
    patterns.push(['头','百','十','尾'].map(k=>escapeRegexLiteral(fields.get(k))).join('-'));
  // Four comma-separated groups are another supported four-position form.
  if(fields.size===4&&['头','百','十','尾'].every(k=>fields.has(k)))
    patterns.push(['头','百','十','尾'].map(k=>escapeRegexLiteral(fields.get(k))).join('[,，]'));
  // Mask shorthand: each X denotes an omitted position; hyphens are visual only.
  // Example: canonical 67头57百38尾 -> source tokens 67,57,X,38 -> "67-57X38".
  const slots=['头','百','十','尾'].map(k=>fields.get(k)||'X');
  if(slots.includes('X'))patterns.push(slots.map(escapeRegexLiteral).join('-?'));
  for(const pattern of patterns){
    const regex=new RegExp(pattern,'g');regex.lastIndex=Math.max(0,from||0);let found;
    while((found=regex.exec(normalized))!==null){
      const at=found.index,end=regex.lastIndex;
      if(end<=at){regex.lastIndex=at+1;continue;}
      if(end>raw.length||occupied.slice(at,end).some(Boolean))continue;
      if(at>0&&/[0-9X]/.test(normalized[at-1]))continue;
      if(end<normalized.length&&/[0-9X]/.test(normalized[end]))continue;
      const source=raw.slice(at,end);occupied.fill(1,at,end);
      return {start:at,end,matched:true,source};
    }
  }
  return {start:0,end:0,matched:false,source:code};
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
  const warningsFor=span=>span.matched?issues.filter(x=>x.severity==='WARNING' && span.start<x.end && span.end>x.start):[];
  // The Android parser marks repeated scatter entries as a DUPLICATE
  // *notice*, not an ERROR. When provenance is verified, these remain valid,
  // independently payable entries. Scope the exception to scatter only.
  // Keep the warning text visible, but do not
  // misclassify this one notice as an unresolved location/recognition failure.
  // Any missing/unknown notice stays fail-closed as "需确认".
  const requiresReview=(warnings,allowScatterDuplicate=false)=>warnings.some(issue=>!allowScatterDuplicate || issue.notice!=='DUPLICATE');
  const warningDescription=warnings=>warnings.map(issue=>issue.message).filter(Boolean).join('；');

  // Locate suite snippets first so that a later ordinary number cannot be
  // incorrectly highlighted inside a preceding multi-position suite.
  const nextSuiteOffset=new Map();
  const suiteRows=suites.map((suite,i)=>{
    const canonical=String(suite.canonical||''), guessed=String(suite.source||canonical);
    const needle=normalizeForOffsets(guessed.split('=')[0]);
    const from=nextSuiteOffset.get(needle)||0;
    let span=locateUnclaimed(raw,normalized,needle,from,occupied);
    if(!span.matched && needle.replace(/[ \t\r\n\u00a0]/g,'')===
      normalizeForOffsets(canonical.split('=')[0]).replace(/[ \t\r\n\u00a0]/g,'')){
      // Preserve fail-closed behavior: only compare the precise authoritative
      // digit/position sequence; this is NOT a new wager recognizer.
      span=locateSuiteWithWhitespace(raw,normalized,canonical,occupied);
    }
    if(!span.matched){
      // The authoritative Kotlin parser may canonicalize legacy aliases before
      // exposing suite.source. Map only spellings proven equivalent to its exact
      // position map; never mark a guessed/unmatched source as verified.
      span=locateSuiteSourceAlias(raw,normalized,canonical,from,occupied);
    }
    if(span.matched)nextSuiteOffset.set(needle,span.end);
    // Legacy shorthand can compile into a canonical expression not literally
    // present in the input. Show the original for audit, but do NOT claim a
    // verified source offset or silently mark it as Normal.
    if(!span.matched&&suites.length===1&&scatter.length===0)span.source=raw;
    const warnings=warningsFor(span), examples=exampleSuite(canonical);
    return {...span,index:i,canonical,amountJiao:Number(suite.amountJiao),
      amountText:moneyJiao(suite.amountJiao),expectedCount:Number(suite.expectedCount),
      examples,recognition:canonical.split('=')[0],
      status:!span.matched||requiresReview(warnings)?'需确认':'正常',
      detail:!span.matched?'预览无法定位该套码在原文中的准确位置，请人工核对':warningDescription(warnings)};
  });

  // Full-turn and normal amounts deliberately re-use each segment's code.
  // First reproduce the AUTHORITATIVE Kotlin execution order strictly for audit;
  // only if every code, amount, mode and slice agrees may we re-use a source span.
  const verified=auditFullTurnSource(raw,normalized,scatter,flags);
  let cursor=0;
  const allScatter=scatter.map((item,i)=>{
    const evidence=verified?.[i];
    const span=evidence?{
      start:evidence.start,end:evidence.end,source:evidence.source,matched:true,
      modeSource:evidence.modeSource,clauseSource:evidence.clauseSource,
      modeSpan:evidence.modeSpan,verifiedGroupKey:evidence.groupKey
    }:locateUnclaimed(raw,normalized,String(item.number),cursor,occupied);
    if(!verified&&span.matched)cursor=span.end;
    const warnings=warningsFor(span);
    return {...span,number:String(item.number),amountJiao:Number(item.amountJiao),
      amountText:moneyJiao(item.amountJiao),isTurn:flags[i],executionIndex:i+1,
      status:!span.matched||requiresReview(warnings,true)?'需确认':'正常',
      detail:!span.matched?'原文中无法定位该执行项的准确来源，请返回核对':warningDescription(warnings)};
  });
  // Android v2.0.21 rule: classification comes from the final number of
  // expanded combinations, not from a Kotlin parser enum or suite syntax.
  // This is display-only: the authoritative p.scatter/p.suites stay unchanged.
  const singlePositionRows=suiteRows.filter(row=>row.expectedCount===1).map(row=>({
    ...row,number:row.examples[0]||row.recognition,isTurn:false,executionIndex:scatter.length+row.index+1
  }));
  const ordinary=[...allScatter.filter(x=>!x.isTurn),...singlePositionRows]
    .sort((a,b)=>(a.matched?a.start:Number.MAX_SAFE_INTEGER)-(b.matched?b.start:Number.MAX_SAFE_INTEGER));
  const turns=allScatter.filter(x=>x.isTurn).map(row=>({
    ...row,permutations:turnPermutationCount(row.number),
    estimatedCostJiao:row.amountJiao*turnPermutationCount(row.number)
  }));
  const multiSuites=suiteRows.filter(x=>x.expectedCount!==1);
  const displayGroups=groupVerifiedSlices(ordinary);
  const groups=new Map();
  for(const item of displayGroups){
    const price=moneyJiao(item.amountJiao);
    if(!groups.has(price))groups.set(price,[]);
    groups.get(price).push(item.number);
  }
  const summary=[...groups].map(([amount,codes])=>`${codes.join('、')}各${amount}`).join('；');
  const all=[...ordinary,...turns,...multiSuites];
  const ordinaryJiao=ordinary.reduce((sum,row)=>sum+row.amountJiao,0);
  const turnJiao=turns.reduce((sum,row)=>sum+row.estimatedCostJiao,0);
  const suiteJiao=multiSuites.reduce((sum,row)=>sum+row.amountJiao*row.expectedCount,0);
  // Only display an estimated total if it EXACTLY matches Kotlin's authority.
  // This is NOT a new parser, nor a new calculator for what will be sent.
  const estimatedTotalVerified=Number.isSafeInteger(ordinaryJiao+turnJiao+suiteJiao) &&
    turns.every(row=>Number.isSafeInteger(row.estimatedCostJiao)) &&
    ordinaryJiao+turnJiao+suiteJiao===Number(p.totalJiao);
  return {scatter:ordinary,turns,suites:multiSuites,ignored,errors:issues.filter(x=>x.severity==='ERROR'),
    warnings:issues.filter(x=>x.severity==='WARNING'),scatterOriginal:displayGroups.map(s=>s.rows[0].source).join('，'),
    scatterRecognition:summary,normalCount:all.filter(x=>x.status==='正常').length,
    reviewCount:all.filter(x=>x.status==='需确认').length,
    failCount:issues.filter(x=>x.severity==='ERROR').length,
    totalCount:all.length+issues.filter(x=>x.severity==='ERROR').length,
    scatterCount:ordinary.length,turnCount:turns.length,suiteCount:multiSuites.length,
    estimatedTotalVerified,turnEstimatedJiao:estimatedTotalVerified?turnJiao:null};
}
