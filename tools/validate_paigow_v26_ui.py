#!/usr/bin/env python3
from pathlib import Path
from html.parser import HTMLParser
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,v):checks.append((n,bool(v)))
class P(HTMLParser):
 def error(self,message):pass
for rel in ['index.html','404.html','b-paigow01.html']:
 p=P();p.feed((root/rel).read_text('utf-8'));ck('html-parse:'+rel,True)
css=(root/'paigow-app.css').read_text('utf-8');ck('css-braces',css.count('{')==css.count('}'));ck('v26-css',all(x in css for x in ['.casino-head','.lobby-grid','.seat-table','.board-frame','.self-zone','.tile3d','.pair-type-label']))
js=(root/'paigow-app.js').read_text('utf-8');ck('no-mock-data',all(x not in js for x in ['顾长风','沈青禾','陆无尘','makeDeck(','allocatePool(']));ck('server-authority',all(x in js for x in ["rpc('get_paigow_lobby_bpaigow01'","rpc('advance_paigow_round_bpaigow01'","rpc('choose_paigow_multiplier_bpaigow01'","rpc('arrange_paigow_big_bpaigow01'"]))
ck('face-render',all(x in js for x in ['tile.face','face.top','face.bottom','class=\"pip ${red.has(n)']))
failed=[n for n,v in checks if not v]
for n,v in checks:print(('PASS ' if v else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
