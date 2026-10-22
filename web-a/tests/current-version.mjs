/** Run historical tests against the current unified A/B/WAP release instead of stale folders/HTML literals. */
import {readFileSync} from 'node:fs';
export const CURRENT_RELEASE=JSON.parse(readFileSync(new URL('../../VERSION.json',import.meta.url),'utf8'));
