import assert from 'node:assert/strict';import http from 'node:http';import {mkdtempSync,rmSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';import {openDatabase} from '../server/db.mjs';import {createApp} from '../server/app.mjs';
const root=mkdtempSync(join(tmpdir(),'verse-platform-'));process.env.DATABASE_PATH=join(root,'test.db');delete process.env.RAZORPAY_KEY_ID;delete process.env.RAZORPAY_KEY_SECRET;const db=openDatabase(root),server=http.createServer(createApp({db,root}));await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}/api`,cookies={};
async function call(path,{method='GET',body,jar}={}){const h={};if(body!==undefined)h['Content-Type']='application/json';if(jar&&cookies[jar])h.Cookie=cookies[jar];const r=await fetch(base+path,{method,headers:h,body:body===undefined?undefined:JSON.stringify(body)});const c=r.headers.get('set-cookie');if(jar&&c)cookies[jar]=c.split(';')[0];return {r,d:await r.json()};}
try{
 let x=await call('/auth/register',{method:'POST',jar:'artist',body:{name:'Live Artist',email:'live@example.com',password:'StrongPass123!',role:'jobseeker'}});assert.equal(x.r.status,201);
 x=await call('/billing/checkout',{method:'POST',jar:'artist',body:{planCode:'pro'}});assert.equal(x.r.status,201);assert.equal(x.d.subscription.status,'trialing');assert.equal(x.d.checkout.mode,'mock');
 x=await call('/acts',{method:'POST',jar:'artist',body:{name:'The QA Collective',actType:'band',city:'Mumbai',genres:['Pop','Bollywood'],lineupSize:4,minFee:75000,maxFee:125000,ownerRole:'Lead Vocalist'}});assert.equal(x.r.status,201);const actId=x.d.id;
 x=await call(`/acts/${actId}/members`,{method:'POST',jar:'artist',body:{displayName:'Session Bassist',roleName:'Bass Guitarist',instrument:'Bass Guitar'}});assert.equal(x.r.status,201);
 x=await call('/auth/login',{method:'POST',jar:'buyer',body:{email:'studio@verse.local',password:'Employer@123'}});assert.equal(x.r.status,200);
 x=await call('/bookings',{method:'POST',jar:'buyer',body:{actId,eventType:'wedding',eventDate:'2026-11-22',city:'Jaipur',venueName:'Test Palace',budgetMin:80000,budgetMax:120000,requirements:'Two 60 minute sets, Bollywood and pop.'}});assert.equal(x.r.status,201);const bookingId=x.d.id;
 x=await call(`/bookings/${bookingId}/quote`,{method:'POST',jar:'artist',body:{performanceFee:95000,travelFee:15000,depositPercent:50,inclusions:'Band performance and standard backline'}});assert.equal(x.r.status,201);
 x=await call(`/bookings/${bookingId}/status`,{method:'POST',jar:'buyer',body:{status:'accepted'}});assert.equal(x.r.status,200);
 x=await call('/band-projects',{method:'POST',jar:'artist',body:{name:'New Live Project',city:'Mumbai',genres:['Indie Pop'],commitmentType:'recurring-gig',compensationModel:'Per show + rehearsal retainer'}});assert.equal(x.r.status,201);const projectId=x.d.id;
 x=await call(`/band-projects/${projectId}/roles`,{method:'POST',jar:'artist',body:{roleName:'Technical Director',countNeeded:1,skillLevel:'touring',requirements:'Own show files and advance production.',compensation:'₹15,000/show'}});assert.equal(x.r.status,201);const roleId=x.d.id;
 x=await call(`/band-projects/${projectId}/roles/${roleId}/publish`,{method:'POST',jar:'artist',body:{}});assert.equal(x.r.status,201);
 x=await call('/organizations',{method:'POST',jar:'artist',body:{name:'QA Artist Workspace',orgType:'band'}});assert.equal(x.r.status,201);const orgId=x.d.id;
 x=await call('/organizations/'+orgId+'/members',{jar:'artist'});assert.equal(x.r.status,200);assert.equal(x.d.members.length,1);
 x=await call(`/bookings/${bookingId}/payment-order`,{method:'POST',jar:'buyer',body:{}});assert.equal(x.r.status,201);assert.equal(x.d.checkout.mode,'mock');const payId=x.d.payment.id;
 x=await call(`/booking-payments/${payId}/confirm`,{method:'POST',jar:'buyer',body:{}});assert.equal(x.r.status,200);
 x=await call(`/bookings/${bookingId}/payments`,{jar:'artist'});assert.equal(x.r.status,200);assert.ok(x.d.payments.some(p=>p.status==='paid'));
 x=await call('/taxonomy');assert.equal(x.r.status,200);assert.ok(x.d.roleCategories.live.includes('Show Runner'));assert.ok(x.d.roleCategories.writing.includes('Composer'));
 console.log('platform smoke: PASS');
}finally{await new Promise(r=>server.close(r));db.close();rmSync(root,{recursive:true,force:true});}
