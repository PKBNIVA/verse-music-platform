import assert from 'node:assert/strict';
import http from 'node:http';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openDatabase} from '../server/db.mjs';
import {createApp} from '../server/app.mjs';

const root=mkdtempSync(join(tmpdir(),'verse-test-'));
process.env.DATABASE_PATH=join(root,'test.db');
const db=openDatabase(root); const server=http.createServer(createApp({db,root}));
await new Promise(r=>server.listen(0,'127.0.0.1',r)); const port=server.address().port; const base=`http://127.0.0.1:${port}/api`;
let cookies={};
async function call(path,{method='GET',body,jar}={}){const headers={};if(body!==undefined)headers['Content-Type']='application/json';if(jar&&cookies[jar])headers.Cookie=cookies[jar];const res=await fetch(base+path,{method,headers,body:body===undefined?undefined:JSON.stringify(body)});const set=res.headers.get('set-cookie');if(jar&&set)cookies[jar]=set.split(';')[0];const data=await res.json();return {res,data};}
try{
  let x=await call('/auth/register',{method:'POST',jar:'c',body:{name:'QA Candidate',email:'qa@example.com',password:'StrongPass123!',role:'jobseeker'}});assert.equal(x.res.status,201);
  x=await call('/auth/login',{method:'POST',jar:'e',body:{email:'studio@verse.local',password:'Employer@123'}});assert.equal(x.res.status,200);
  x=await call('/jobs',{method:'POST',jar:'e',body:{title:'QA Session Vocalist',location:'Mumbai',opportunityKind:'session',functionArea:'Performance',workplace:'onsite',type:'Project-based',genre:'Pop',description:'A paid studio session requiring prepared demo references, punctual attendance, clean takes and collaborative work with the producer.',skills:['Vocals'],compensationMin:5000,compensationMax:8000,paid:true}});assert.equal(x.res.status,201);const jobId=x.data.id;
  x=await call('/auth/login',{method:'POST',jar:'a',body:{email:'admin@verse.local',password:'Admin@12345'}});assert.equal(x.res.status,200);
  x=await call(`/admin/jobs/${jobId}`,{method:'PATCH',jar:'a',body:{status:'published'}});assert.equal(x.res.status,200);
  x=await call(`/saved-jobs/${jobId}`,{method:'POST',jar:'c'});assert.equal(x.res.status,201);
  x=await call(`/jobs/${jobId}/apply`,{method:'POST',jar:'c',body:{coverLetter:'Relevant studio experience.'}});assert.equal(x.res.status,201);
  x=await call('/employer/applications',{jar:'e'});assert.equal(x.res.status,200);const app=x.data.applications.find(a=>a.jobId===jobId);assert.ok(app);
  x=await call(`/employer/applications/${app.id}`,{method:'PATCH',jar:'e',body:{status:'Shortlisted'}});assert.equal(x.res.status,200);
  x=await call('/notifications',{jar:'c'});assert.equal(x.res.status,200);assert.ok(x.data.notifications.some(n=>n.type==='application_status'));
  x=await call('/reports',{method:'POST',jar:'c',body:{entityType:'job',entityId:jobId,reason:'QA report'}});assert.equal(x.res.status,201);
  x=await call('/admin/stats',{jar:'a'});assert.equal(x.res.status,200);assert.ok(x.data.stats.applications>=1);assert.ok(x.data.stats.openReports>=1);
  console.log('backend smoke: PASS');
} finally {await new Promise(r=>server.close(r));db.close();rmSync(root,{recursive:true,force:true});}
