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

const legal = await read('../src/app/pages/public/LegalPage.tsx');
assert.doesNotMatch(legal, /starter terms|before launch|replace this placeholder|operational starter copy|production launch should|production operations should/i, 'public legal pages must not expose internal launch instructions');
assert.match(legal, /Browser Storage & Session Notice/, 'session notice must describe the implemented browser storage model');
assert.doesNotMatch(legal, /HttpOnly cookie/, 'session notice must not claim an unimplemented cookie model');
assert.match(legal, /mailto:/, 'support pages must provide an actionable contact link');

const availability = await read('../src/app/pages/Availability.tsx');
assert.match(availability, /validRange/, 'availability submission must validate its date range before calling the API');
assert.match(availability, /Try again/, 'availability load failures must provide a retry action');
assert.match(availability, /Unable to remove availability/, 'availability deletion failures must be visible');

const workspace = await read('../src/app/pages/Workspace.tsx');
assert.match(workspace, /Unable to load workspaces/, 'workspace load failures must be visible');
assert.match(workspace, /window\.confirm/, 'member removal must require confirmation');

const adminTester = await read('../src/app/pages/AdminTester.tsx');
assert.match(adminTester, /Unable to run platform checks/, 'admin runtime check failures must be visible');

const catalogs = await Promise.all([
  read('../src/app/pages/public/PublicJobs.tsx'),
  read('../src/app/pages/public/PublicTalent.tsx'),
  read('../src/app/pages/public/PublicActs.tsx'),
]);
for (const source of catalogs) assert.match(source, /auth\//, 'empty public catalogs must offer a useful account action');

console.log('frontend resilience smoke: ok');
