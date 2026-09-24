import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const publicPages = await Promise.all([
  read('../src/app/pages/public/PublicOpportunity.tsx'),
  read('../src/app/pages/public/PublicProfile.tsx'),
  read('../src/app/pages/public/PublicAct.tsx'),
  read('../src/app/pages/public/PublicActs.tsx'),
]);

for (const source of publicPages) {
  assert.match(source, /setLoading\(true\)/, 'public API screens must expose a loading state');
  assert.match(source, /setError\(/, 'public API screens must expose request failures');
  assert.match(source, /Try again/, 'public API screens must provide a retry action');
}
assert.match(publicPages[3], /acts\.length===0/, 'the public act catalog must distinguish an empty result from a failed request');

const notifications = await read('../src/app/pages/Notifications.tsx');
assert.doesNotMatch(notifications, /catch\(\(\)=>\{\}\)/, 'notification failures must not be swallowed');
assert.match(notifications, /setItems\(xs=>xs\.map\(x=>x\.id===n\.id\?\{\.\.\.x,readAt\}:x\)\)/, 'mark-read must update optimistically');
assert.match(notifications, /catch\(e:any\)\{setItems\(xs=>xs\.map\(x=>x\.id===n\.id\?\{\.\.\.x,readAt:null\}:x\)\)/, 'mark-read failure must roll back optimistic state');

const jobDetails = await read('../src/app/pages/JobDetails.tsx');
assert.match(jobDetails, /user\?\.role==='jobseeker'&&<div className="flex gap-2 mb-5">/, 'save and report controls must be limited to jobseekers');

console.log('frontend resilience smoke: ok');
