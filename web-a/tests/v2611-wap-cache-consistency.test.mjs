import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const release=JSON.parse(readFileSync(new URL('../../VERSION.json',import.meta.url),'utf8'));
const app=readFileSync(new URL('../site/app.js',import.meta.url),'utf8');
const html=readFileSync(new URL('../site/index.html',import.meta.url),'utf8');
const api=readFileSync(new URL('../site/supabase.js',import.meta.url),'utf8');
assert.ok(html.includes(`app.js?v=${release.versionName}`));
assert.ok(html.includes(`parser.js?v=${release.versionName}`));
const imports=[...app.matchAll(/from ['"](\.\/[^'"]+)['"]/g)].map(m=>m[1]);
assert.ok(imports.length>=10,'all modular imports should be explicit');
for (const link of imports){
  assert.ok(link.endsWith(`?v=${release.versionName}`),`stale module cache key: ${link}`);
}
for(const method of ['tasks','orders','queueState','enqueueOrder','cancelQueuedOrder','reviewCloseOrder'])
  assert.match(api,new RegExp(`async ${method}\\(`),`missing API method: ${method}`);
assert.match(app,/requiredApiMethods/);
console.log('PASS current WAP cache keys and Supabase orders API');
