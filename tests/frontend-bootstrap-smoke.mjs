import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const authSource = await readFile(new URL('../src/app/lib/authContext.tsx', import.meta.url), 'utf8');
const navigationSource = await readFile(new URL('../src/app/components/Navigation.tsx', import.meta.url), 'utf8');

assert.match(
  authSource,
  /if\s*\(\s*!hasAccessToken\(\)\s*\)\s*\{[^}]*setLoading\(false\)[^}]*return/s,
  'anonymous auth hydration must finish without requesting /me',
);
assert.match(authSource, /apiGet<\{user:User\}>\('\/me'\)/, 'stored sessions must still be validated with /me');

assert.match(
  navigationSource,
  /apiGet<any>\('\/notifications\/unread'\)/,
  'workspace navigation must request the lightweight unread-count endpoint',
);
assert.doesNotMatch(
  navigationSource,
  /apiGet<any>\('\/notifications'\)/,
  'workspace navigation must not download the full notification list',
);
assert.match(
  navigationSource,
  /apiGet<any>\('\/notifications\/unread'\)[\s\S]*?\},\s*\[\]\s*\)/,
  'navigation unread loading must not be explicitly coupled to pathname changes',
);

console.log('frontend bootstrap smoke: ok');
