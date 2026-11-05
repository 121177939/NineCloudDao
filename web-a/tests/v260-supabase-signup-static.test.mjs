import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const html=readFileSync(new URL('../site/index.html',import.meta.url),'utf8');
const api=readFileSync(new URL('../site/supabase.js',import.meta.url),'utf8');
const app=readFileSync(new URL('../site/app.js',import.meta.url),'utf8');
for(const id of ['register-toggle','register-panel','register-confirm','register-submit'])
 assert(html.includes('id="'+id+'"'));
assert(api.includes("'/auth/v1/signup'"));
assert(app.includes("$('register-submit').addEventListener"));
assert(!api.includes('BOOTSTRAP_KEY'));
console.log('PASS Supabase WAP registration is independent from Worker bootstrap');
