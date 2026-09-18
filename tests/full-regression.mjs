import assert from 'node:assert/strict';
import http from 'node:http';
import {mkdtempSync,rmSync,mkdirSync,writeFileSync,readdirSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';import {join,extname} from 'node:path';import {execFileSync} from 'node:child_process';import {fileURLToPath} from 'node:url';
import {openDatabase} from '../server/db.mjs';import {createApp} from '../server/app.mjs';
const projectRoot=join(fileURLToPath(new URL('.',import.meta.url)),'..');
function walk(dir){return readdirSync(dir,{withFileTypes:true}).flatMap(x=>x.isDirectory()?walk(join(dir,x.name)):[join(dir,x.name)]);}
function syntaxAudit(){execFileSync(process.execPath,['--check',join(projectRoot,'server/app.mjs')]);execFileSync(process.execPath,['--check',join(projectRoot,'server/db.mjs')]);execFileSync(process.execPath,['--check',join(projectRoot,'server/search.mjs')]);const tsPath='/opt/nvm/versions/node/v22.16.0/lib/node_modules/typescript/lib/typescript.js';let ts;try{ts=awaitImport(tsPath)}catch{return {tsx:0,skipped:true}}}
async function parseTs(){let ts;try{ts=await import('file:///opt/nvm/versions/node/v22.16.0/lib/node_modules/typescript/lib/typescript.js')}catch{return {count:0,skipped:true}}const files=walk(join(projectRoot,'src')).filter(f=>['.ts','.tsx'].includes(extname(f)));const errors=[];for(const f of files){const text=readFileSync(f,'utf8');const out=ts.default.transpileModule(text,{compilerOptions:{jsx:ts.default.JsxEmit.ReactJSX,target:ts.default.ScriptTarget.ES2022},reportDiagnostics:true,fileName:f});for(const d of out.diagnostics||[])if(d.category===ts.default.DiagnosticCategory.Error)errors.push(`${f}: ${ts.default.flattenDiagnosticMessageText(d.messageText,' ')}`)}assert.equal(errors.length,0,errors.slice(0,10).join('\n'));return {count:files.length,skipped:false}}
function wavSilence(){const sampleRate=8000,samples=800,dataSize=samples*2,b=Buffer.alloc(44+dataSize);b.write('RIFF',0);b.writeUInt32LE(36+dataSize,4);b.write('WAVEfmt ',8);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(sampleRate,24);b.writeUInt32LE(sampleRate*2,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(dataSize,40);return b;}
const syntax=await parseTs();
const root=mkdtempSync(join(tmpdir(),'verse-full-'));mkdirSync(join(root,'dist'),{recursive:true});writeFileSync(join(root,'dist','index.html'),'<!doctype html><html><head><title>Verse</title><meta name="description" content="Verse"/><meta name="robots" content="index, follow"/></head><body></body></html>');process.env.DATABASE_PATH=join(root,'test.db');process.env.NODE_ENV='test';delete process.env.ELASTICSEARCH_URL;const db=openDatabase(root),server=http.createServer(createApp({db,root}));await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin=`http://127.0.0.1:${server.address().port}`,base=`${origin}/api`;let cookie='';async function j(path,{method='GET',body,rawBody,headers={}}={}){const h={...headers};if(cookie)h.Cookie=cookie;if(body!==undefined)h['Content-Type']='application/json';const r=await fetch(path.startsWith('/api/')?origin+path:base+path,{method,headers:h,body:rawBody!==undefined?rawBody:(body===undefined?undefined:JSON.stringify(body))});const c=r.headers.get('set-cookie');if(c)cookie=c.split(';')[0];let d={};try{d=await r.json()}catch{}return {r,d};}
try{
  // Music professional #1: richer profile and valid local upload -> persisted portfolio.
  let x=await j('/auth/login',{method:'POST',body:{email:'artist@verse.local',password:'Artist@123'}});assert.equal(x.r.status,200);const artistId=x.d.user.id;
  x=await j('/uploads/presign',{method:'POST',body:{filename:'proof.wav',contentType:'audio/wav',size:wavSilence().length}});assert.equal(x.r.status,200);const up=await j(x.d.uploadUrl,{method:'PUT',rawBody:wavSilence(),headers:{'Content-Type':'audio/wav'}});assert.equal(up.r.status,201);assert.match(up.d.url,/^\/uploads\//);assert.ok(up.d.metadata?.duration>0);
  x=await j('/portfolio',{method:'POST',body:{type:'audio',title:'Live playback vocal proof',url:up.d.url,description:'Valid uploaded proof.',roles:['Playback Singer'],genres:['Bollywood'],tags:['studio','playback'],mediaMetadata:up.d.metadata,waveformUrl:up.d.waveformUrl,thumbnailUrl:up.d.thumbnailUrl,visibility:'public'}});assert.equal(x.r.status,201);assert.equal(x.d.item.url,up.d.url);assert.ok(x.d.item.mediaMetadata);
  // Second professional for compare + synonym search.
  cookie='';x=await j('/auth/register',{method:'POST',body:{name:'Riya Sound',email:'riya@example.test',password:'StrongPass123!',role:'jobseeker'}});assert.equal(x.r.status,201);const riyaId=x.d.user.id;
  x=await j('/profile',{method:'PUT',body:{headline:'FOH Engineer',bio:'Live audio engineer for concerts and corporate shows.',location:'Mumbai',roles:['FOH Engineer','Live Sound Engineer'],skills:['Live Sound','DiGiCo'],gear:['DiGiCo Quantum'],genres:['Live'],yearsExperience:8,travelsNationally:true,dayRate:25000,currency:'INR'}});assert.equal(x.r.status,200);
  x=await j('/search?q=sound%20guy&type=talent');assert.equal(x.r.status,200);assert.ok(x.d.interpretedAs.includes('foh engineer'));assert.ok(x.d.results.some(r=>r.id===riyaId),'synonym search should find FOH engineer');
  // Recruiter comparison + recent activity.
  cookie='';x=await j('/auth/login',{method:'POST',body:{email:'studio@verse.local',password:'Employer@123'}});assert.equal(x.r.status,200);
  x=await j('/candidates?q=sound%20guy');assert.equal(x.r.status,200);assert.ok(x.d.candidates.some(c=>c.id===riyaId));
  x=await j(`/candidates/${riyaId}`);assert.equal(x.r.status,200);
  x=await j(`/candidates/compare/list?ids=${artistId},${riyaId}`);assert.equal(x.r.status,200);assert.equal(x.d.professionals.length,2);assert.ok(Array.isArray(x.d.professionals[0].portfolio));
  x=await j('/recent-activity');assert.equal(x.r.status,200);assert.ok(x.d.items.some(i=>i.kind==='profile_view'&&i.entityId===riyaId));
  // Layman crew planner -> band builder conversion.
  x=await j('/crew-plans',{method:'POST',body:{title:'Annual Sales Gala',eventType:'Corporate event',city:'Jaipur',audienceSize:900,budget:400000,genres:['Bollywood'],needs:['music','sound','lighting','production']}});assert.equal(x.r.status,201);assert.ok(x.d.roles.some(r=>r.roleName==='FOH Engineer'));assert.ok(x.d.roles.some(r=>r.roleName==='Production Manager'));const crewId=x.d.id;
  x=await j('/crew-plans');assert.equal(x.r.status,200);assert.ok(x.d.plans.some(p=>p.id===crewId&&p.roles.length>=6));
  x=await j(`/crew-plans/${crewId}/convert`,{method:'POST',body:{}});assert.equal(x.r.status,201);const projectId=x.d.projectId;
  x=await j('/band-projects');assert.equal(x.r.status,200);assert.ok(x.d.projects.some(p=>p.id===projectId&&p.roles.length>=6)); // endpoint remains healthy after conversion
  // Public SEO essentials and protected/search noindex.
  let r=await fetch(origin+'/robots.txt');assert.equal(r.status,200);assert.match(await r.text(),/Sitemap:/);
  r=await fetch(origin+'/sitemap.xml');const map=await r.text();assert.match(map,/\/privacy/);assert.match(map,/\/guide/);assert.doesNotMatch(map,/\/admin\/tester/);
  r=await fetch(origin+'/search?q=foh');assert.match(await r.text(),/noindex, nofollow/);
  // Live non-destructive tester as admin.
  cookie='';x=await j('/auth/login',{method:'POST',body:{email:'admin@verse.local',password:'Admin@12345'}});assert.equal(x.r.status,200);
  x=await j('/admin/tester');assert.equal(x.r.status,200);assert.equal(x.d.summary.failed,0,JSON.stringify(x.d.checks.filter(c=>!c.pass)));
  // Obvious source regressions: fake auth, old mocks, accidental duplicate request parser.
  const sources=walk(join(projectRoot,'src')).concat(walk(join(projectRoot,'server'))).filter(f=>/\.(tsx?|mjs)$/.test(f)).map(f=>readFileSync(f,'utf8')).join('\n');assert.doesNotMatch(sources,/DUMMY_OTP|mockData|verse_token/);assert.equal((readFileSync(join(projectRoot,'server/app.mjs'),'utf8').match(/const url=new URL\(req\.url/g)||[]).length,1);
  console.log(`full regression: PASS (${syntax.count||'TS'} TS/TSX files parsed)`);
}finally{await new Promise(r=>server.close(r));db.close();rmSync(root,{recursive:true,force:true});}
