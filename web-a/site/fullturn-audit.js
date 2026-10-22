// Stage eight · strict source-provenance audit for Kotlin FullTurnParser output.
// NEVER used to accept a bet, infer a missing command, or change the M1 wire.
// Trust a located span only when ALL reconstructed execution slices match
// the authoritative Kotlin/JS scatter items and F flags, one by one.
const TURN=/^全(?:倒|到|转)/;
const AMOUNT=/^(?:各打|各|打)\s*([0-9]+(?:\.[0-9])?)\s*(?:组|元|块)?|^([0-9]+(?:\.[0-9])?)\s*(?:组|元|块)?/;
const DASH=/^[-=]\s*([0-9]+(?:\.[0-9])?)\s*(?:组|元|块)?/;
const CODE=/^[0-9X]{4}(?![0-9X])/;
const SEPARATORS=' ,，、;；。\r\n\t';
const pMoney=str=>{
  if(!/^\d+(?:\.\d)?$/.test(str))return null;
  const [whole,decimal='']=str.split('.');
  const out=Number(whole)*10+Number(decimal||0);
  return Number.isSafeInteger(out)&&out>0?out:null;
};
export function auditFullTurnSource(raw,normalized,authoritative,flags) {
  const items=Array.isArray(authoritative)?authoritative:[];
  if(!items.length||!Array.isArray(flags)||flags.length!==items.length)return null;
  // Do not use this dedicated parser-audit path on mixed named-position suites.
  if(/(?<![0-9X])(?:[0-9]{1,10}[头百十尾个]|全[头百十尾])/.test(normalized))return null;
  if(!/全(?:倒|到|转)/.test(normalized))return null;
  const spans=[];let pos=0,segmentIndex=0;
  const skip=()=>{while(pos<normalized.length&&SEPARATORS.includes(normalized[pos]))pos++;};
  const peek=re=>normalized.slice(pos).match(re);
  function readAmount(regex=AMOUNT){
    const m=peek(regex);if(!m)return null;
    const money=pMoney(m[1]||m[2]);
    if(money===null)return null;
    const start=pos;pos+=m[0].length;
    return {jiao:money,start,end:pos,source:raw.slice(start,pos)};
  }
  function addSlices(codes,amount,isTurn,seg){
    for(const c of codes){
      let left=amount.jiao;
      const groupKey=`${seg}:${c.codeIndex}:${isTurn?'T':'N'}`;
      while(left>0){
        const jiao=Math.min(left,500);
        spans.push({number:c.number,amountJiao:jiao,isTurn,start:c.start,end:c.end,
          source:raw.slice(c.start,c.end),modeSpan:{start:amount.start,end:amount.end},
          clauseSource:raw.slice(c.segmentStart,amount.end),modeSource:amount.source,
          groupKey,segmentIndex:seg});
        left-=jiao;
      }
    }
  }
  skip();
  while(pos<normalized.length){
    const segStart=pos,codes=[];
    while(true){
      const m=peek(CODE);if(!m||m[0].split('X').length>3)break;
      codes.push({number:m[0],start:pos,end:pos+m[0].length,segmentStart:segStart,codeIndex:codes.length});
      pos+=m[0].length;
      while(pos<normalized.length&&' 、,，\t\r\n'.includes(normalized[pos]))pos++;
      if(!peek(CODE))break;
    }
    if(!codes.length)return null;
    while(pos<normalized.length&&' \t\r\n'.includes(normalized[pos]))pos++;
    const alone=peek(TURN);
    let normal=null,turn=null;
    if(!alone){
      normal=readAmount();
      if(!normal&&codes.length===1&&/^\d{4}$/.test(codes[0].number))normal=readAmount(DASH);
      if(!normal)return null;
      skip();
    }
    const turnToken=peek(TURN);
    if(turnToken){
      const turnStart=pos;
      pos+=turnToken[0].length;
      while(pos<normalized.length&&' \t\r\n'.includes(normalized[pos]))pos++;
      turn=readAmount();
      if(!turn)return null;
      turn.start=turnStart;
      turn.source=raw.slice(turnStart,turn.end);
    }
    if(normal)addSlices(codes,normal,false,segmentIndex);
    if(turn)addSlices(codes,turn,true,segmentIndex);
    segmentIndex++;skip();
  }
  if(spans.length!==items.length)return null;
  for(let i=0;i<spans.length;i++){
    if(spans[i].number!==String(items[i].number)||spans[i].amountJiao!==Number(items[i].amountJiao)||spans[i].isTurn!==flags[i])return null;
  }
  return spans;
}

// Group ONLY slices from the same verified source occurrence and same mode;
// distinct occurrences/repeated orders stay distinct. Never changes the wire.
export function groupVerifiedSlices(rows) {
  const groups=[];
  for(const row of Array.isArray(rows)?rows:[]){
    const key=row.verifiedGroupKey;
    const previous=key&&groups.find(g=>g.key===key);
    if(previous){previous.amountJiao+=row.amountJiao;previous.parts.push(row.amountJiao);previous.rows.push(row);}
    else groups.push({key:key||null,number:row.number,amountJiao:row.amountJiao,
      parts:[row.amountJiao],rows:[row],modeSource:row.modeSource||'',clauseSource:row.clauseSource||''});
  }
  return groups;
}

// Matches Android FullTurnAmount.multiplier: target app expands unique
// permutations (four digits / repeated digits), not four separate slots.
export function turnPermutationCount(number) {
  const code=String(number||'');
  if(!/^[0-9X]{4}$/.test(code)||[...code].filter(x=>x==='X').length>2)return null;
  const counts=new Map();
  for(const ch of code)counts.set(ch,(counts.get(ch)||0)+1);
  const factorial=[1,1,2,6,24];
  return 24/[...counts.values()].reduce((p,n)=>p*factorial[n],1);
}
