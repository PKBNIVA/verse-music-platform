import http from 'node:http';
import zlib from 'node:zlib';
import crypto from 'node:crypto';

const port = process.env.PORT || 10000;
const API_URL = 'https://backend.aisensy.com/campaign/t1/api/v2';
const CAMPAIGN = 'Praveen Kumar QR API Test';
const NORMALIZER = 'https://aisensy-media-normalizer.onrender.com';
const RUN_TOKEN = 'bulk-20260920-jlc-final';
const EXPECTED_COUNT = 1058;
const EXPECTED_B64_LENGTH = 54512;
const EXPECTED_COMPRESSED_SHA256 = '68657959923ff8afc2943372fdb27e990775c591f3440581b167fb8b17589a02';
let state = { phase: 'ready', total: 0, checked: 0, sent: 0, failed: 0, lastRow: null, error: null, startedAt: null, completedAt: null };
let running = false;
let results = [];
let stop = false;

function payloadDiagnostics() {
  const chunks = [1,2,3,4].map(i => process.env[`BULK_DATA_BR_${i}`] || '');
  const b64 = chunks.join('') || process.env.BULK_DATA_BR || '';
  let decoded = Buffer.alloc(0);
  try { decoded = Buffer.from(b64, 'base64'); } catch {}
  const sha = decoded.length ? crypto.createHash('sha256').update(decoded).digest('hex') : null;
  return { b64Length: b64.length, decodedSha256: sha, lengthOk: b64.length === EXPECTED_B64_LENGTH, shaOk: sha === EXPECTED_COMPRESSED_SHA256 };
}

function loadRows() {
  const b64 = [1,2,3,4].map(i => process.env[`BULK_DATA_BR_${i}`] || '').join('') || process.env.BULK_DATA_BR;
  const diag = payloadDiagnostics();
  if (!diag.lengthOk || !diag.shaOk) throw new Error(`bulk payload integrity mismatch ${JSON.stringify(diag)}`);
  const rows = JSON.parse(zlib.brotliDecompressSync(Buffer.from(b64, 'base64')).toString('utf8'));
  if (!Array.isArray(rows) || rows.length !== EXPECTED_COUNT) throw new Error(`recipient count mismatch: ${rows?.length}`);
  const phones = new Set(rows.map(x => x.p));
  const qrs = new Set(rows.map(x => x.q));
  if (phones.size !== rows.length || qrs.size !== rows.length) throw new Error('duplicate phone/QR detected');
  for (const x of rows) if (!x.r || !x.n || !/^\+91\d{10}$/.test(x.p || '') || !/^https:\/\/eventhug-5f90dbe31c80\.herokuapp\.com\//.test(x.q || '')) throw new Error(`invalid row ${x.r}`);
  return rows;
}

function mediaUrl(row) {
  const token = Buffer.from(row.q, 'utf8').toString('base64url');
  return `${NORMALIZER}/q/${row.r}/${token}.jpg`;
}

async function verifyAndSend(row) {
  const url = mediaUrl(row);
  const pf = await fetch(url, { method: 'HEAD', signal: AbortSignal.timeout(30000) });
  const type = pf.headers.get('content-type') || '';
  const len = Number(pf.headers.get('content-length') || 0);
  if (!pf.ok || type !== 'image/jpeg' || len < 1000 || len > 5_000_000) throw new Error(`media check failed row=${row.r} status=${pf.status} type=${type} len=${len}`);
  state.checked++;

  const payload = {
    apiKey: process.env.AISENSY_API_KEY,
    campaignName: CAMPAIGN,
    destination: row.p,
    userName: row.n,
    source: 'JLC',
    media: { url, filename: `qr-${row.r}.jpg` },
    templateParams: [row.n]
  };
  const started = new Date().toISOString();
  const r = await fetch(API_URL, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload), signal: AbortSignal.timeout(30000) });
  const text = await r.text();
  let parsed = null; try { parsed = JSON.parse(text); } catch {}
  const accepted = r.ok && String(parsed?.success) === 'true' && Boolean(parsed?.submitted_message_id);
  const audit = { csvRow: row.r, name: row.n, phone: row.p, startedAt: started, httpStatus: r.status, accepted: Boolean(accepted), messageId: parsed?.submitted_message_id || null, mediaBytes: len, response: accepted ? 'accepted' : text.slice(0,300) };
  results.push(audit);
  console.log('AUDIT', JSON.stringify(audit));
  if (!accepted) throw new Error(`AiSensy rejected row ${row.r}: ${text}`);
  state.sent++;
  state.lastRow = row.r;
  if (state.sent % 50 === 0) console.log('SEND_PROGRESS', state.sent, '/', state.total);
}

async function runBulk() {
  if (running || state.phase !== 'ready') return state;
  running = true; stop = false;
  const startedAt = new Date().toISOString();
  try {
    const rows = loadRows();
    state = { phase: 'sending', total: rows.length, checked: 0, sent: 0, failed: 0, lastRow: null, error: null, startedAt, completedAt: null };
    console.log('BULK_START', JSON.stringify({ total: rows.length, campaign: CAMPAIGN, startedAt, mode: 'verify-per-recipient-concurrency-6' }));
    let cursor = 0;
    async function worker() {
      while (!stop) {
        const i = cursor++;
        if (i >= rows.length) return;
        const row = rows[i];
        try { await verifyAndSend(row); }
        catch (e) {
          stop = true; state.failed++; state.phase = 'stopped_on_error'; state.error = String(e); state.lastRow = row.r;
          console.error('BULK_STOP', JSON.stringify(state));
          return;
        }
      }
    }
    await Promise.all(Array.from({length:6}, worker));
    if (!stop) { state.phase = 'complete'; state.completedAt = new Date().toISOString(); console.log('BULK_COMPLETE', JSON.stringify(state)); }
    else state.completedAt = new Date().toISOString();
  } catch (e) {
    state.phase = 'aborted'; state.error = String(e); state.completedAt = new Date().toISOString(); console.error('BULK_ABORT', JSON.stringify(state));
  } finally { running = false; }
  return state;
}

function sendJson(res,obj,status=200){const body=JSON.stringify(obj);res.statusCode=status;res.setHeader('content-type','application/json');res.setHeader('content-length',Buffer.byteLength(body));res.end(body)}

http.createServer((req,res)=>{
  const u=new URL(req.url,'http://localhost');
  if(u.pathname==='/status') return sendJson(res,state);
  if(u.pathname==='/results'){const offset=Math.max(0,Number(u.searchParams.get('offset')||0));const limit=Math.min(250,Math.max(1,Number(u.searchParams.get('limit')||100)));return sendJson(res,{total:results.length,offset,items:results.slice(offset,offset+limit)});}
  if(u.pathname===`/run/${RUN_TOKEN}`||u.pathname==='/execute-praveen-test-7f2c'){if(!running&&state.phase==='ready')runBulk().catch(()=>{});return sendJson(res,{accepted:true,state},202)}
  return sendJson(res,{error:'not found'},404);
}).listen(port,'0.0.0.0',()=>{console.log('BULK_SENDER_READY');console.log('PAYLOAD_BOOT_DIAG',JSON.stringify(payloadDiagnostics()))});
