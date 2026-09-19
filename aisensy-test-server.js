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
let state = { phase: 'ready', total: 0, preflightPassed: 0, sent: 0, mediaFetched: 0, failed: 0, lastRow: null, error: null, startedAt: null, completedAt: null };
let running = false;
let results = [];
let preflight = [];

function payloadDiagnostics() {
  const chunks = [1,2,3,4].map(i => process.env[`BULK_DATA_BR_${i}`] || '');
  const b64 = chunks.join('') || process.env.BULK_DATA_BR || '';
  let decoded = Buffer.alloc(0);
  try { decoded = Buffer.from(b64, 'base64'); } catch {}
  return {
    chunkLengths: chunks.map(x => x.length),
    b64Length: b64.length,
    expectedB64Length: EXPECTED_B64_LENGTH,
    decodedLength: decoded.length,
    decodedSha256: decoded.length ? crypto.createHash('sha256').update(decoded).digest('hex') : null,
    expectedSha256: EXPECTED_COMPRESSED_SHA256,
    lengthOk: b64.length === EXPECTED_B64_LENGTH,
    shaOk: decoded.length ? crypto.createHash('sha256').update(decoded).digest('hex') === EXPECTED_COMPRESSED_SHA256 : false
  };
}

function loadRows() {
  const chunks = [1,2,3,4].map(i => process.env[`BULK_DATA_BR_${i}`] || '');
  const b64 = chunks.join('') || process.env.BULK_DATA_BR;
  if (!b64) throw new Error('bulk data missing');
  const diag = payloadDiagnostics();
  console.log('PAYLOAD_DIAG', JSON.stringify(diag));
  if (!diag.lengthOk || !diag.shaOk) throw new Error(`bulk payload integrity mismatch ${JSON.stringify(diag)}`);
  const json = zlib.brotliDecompressSync(Buffer.from(b64, 'base64')).toString('utf8');
  const rows = JSON.parse(json);
  if (!Array.isArray(rows) || rows.length !== EXPECTED_COUNT) throw new Error(`recipient count mismatch: ${rows?.length}`);
  const phones = new Set(rows.map(x => x.p));
  const qrs = new Set(rows.map(x => x.q));
  if (phones.size !== rows.length) throw new Error('duplicate phone detected');
  if (qrs.size !== rows.length) throw new Error('duplicate QR detected');
  for (const x of rows) {
    if (!x.r || !x.n || !/^\+91\d{10}$/.test(x.p || '') || !/^https:\/\/eventhug-5f90dbe31c80\.herokuapp\.com\//.test(x.q || '')) throw new Error(`invalid row ${x.r}`);
  }
  return rows;
}

function mediaUrl(row) {
  const token = Buffer.from(row.q, 'utf8').toString('base64url');
  return `${NORMALIZER}/q/${row.r}/${token}.jpg`;
}

async function hitCount(row) {
  const r = await fetch(`${NORMALIZER}/hit/${row.r}`, { signal: AbortSignal.timeout(15000) });
  if (!r.ok) throw new Error(`hit status unavailable row=${row.r}`);
  const j = await r.json();
  return Number(j.get || 0);
}

async function preflightOne(row) {
  const url = mediaUrl(row);
  const r = await fetch(url, { method: 'HEAD', signal: AbortSignal.timeout(45000) });
  const type = r.headers.get('content-type') || '';
  const len = Number(r.headers.get('content-length') || 0);
  if (!r.ok || type !== 'image/jpeg' || len < 1000 || len > 5_000_000) throw new Error(`media preflight failed row=${row.r} status=${r.status} type=${type} len=${len}`);
  return { csvRow: row.r, name: row.n, phone: row.p, mediaStatus: r.status, mediaType: type, mediaBytes: len, ok: true };
}

async function preflightAll(rows) {
  state.phase = 'preflight';
  const concurrency = 8;
  let cursor = 0;
  const failures = [];
  async function worker() {
    while (true) {
      const i = cursor++;
      if (i >= rows.length) return;
      const row = rows[i];
      try {
        const p = await preflightOne(row);
        preflight.push(p);
        state.preflightPassed++;
        if (state.preflightPassed % 50 === 0) console.log('PREFLIGHT_PROGRESS', state.preflightPassed, '/', rows.length);
      } catch (e) {
        const failure = { csvRow: row.r, name: row.n, phone: row.p, ok: false, error: String(e) };
        preflight.push(failure);
        failures.push(failure);
        console.error('PREFLIGHT_FAIL', JSON.stringify(failure));
      }
    }
  }
  await Promise.all(Array.from({ length: concurrency }, worker));
  if (failures.length) throw new Error(`preflight failed for ${failures.length} rows; first=${JSON.stringify(failures[0])}`);
  console.log('PREFLIGHT_COMPLETE', rows.length);
}

async function waitForMediaFetch(row, baseline) {
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    await new Promise(r => setTimeout(r, 350));
    const count = await hitCount(row);
    if (count > baseline) return count;
  }
  throw new Error(`AiSensy did not GET media for row ${row.r} within 15s`);
}

async function sendOne(row) {
  const baseline = await hitCount(row);
  const payload = {
    apiKey: process.env.AISENSY_API_KEY,
    campaignName: CAMPAIGN,
    destination: row.p,
    userName: row.n,
    source: 'JLC',
    media: { url: mediaUrl(row), filename: `qr-${row.r}.jpg` },
    templateParams: [row.n]
  };
  const started = new Date().toISOString();
  const r = await fetch(API_URL, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload), signal: AbortSignal.timeout(45000) });
  const text = await r.text();
  let parsed = null;
  try { parsed = JSON.parse(text); } catch {}
  const accepted = r.ok && String(parsed?.success) === 'true' && Boolean(parsed?.submitted_message_id);
  if (!accepted) {
    const fail = { csvRow: row.r, name: row.n, phone: row.p, startedAt: started, httpStatus: r.status, accepted: false, mediaFetched: false, messageId: parsed?.submitted_message_id || null, response: text.slice(0, 500) };
    results.push(fail);
    console.error('AUDIT', JSON.stringify(fail));
    throw new Error(`AiSensy rejected row ${row.r}: ${text}`);
  }
  const getCount = await waitForMediaFetch(row, baseline);
  const audit = { csvRow: row.r, name: row.n, phone: row.p, startedAt: started, acceptedAt: new Date().toISOString(), httpStatus: r.status, accepted: true, mediaFetched: true, mediaGetCount: getCount, messageId: parsed.submitted_message_id, response: 'accepted_and_media_fetched' };
  results.push(audit);
  console.log('AUDIT', JSON.stringify(audit));
  return audit;
}

async function runBulk() {
  if (running || state.phase !== 'ready') return state;
  running = true;
  const startedAt = new Date().toISOString();
  try {
    const rows = loadRows();
    state = { phase: 'loaded', total: rows.length, preflightPassed: 0, sent: 0, mediaFetched: 0, failed: 0, lastRow: null, error: null, startedAt, completedAt: null };
    console.log('BULK_START', JSON.stringify({ total: rows.length, campaign: CAMPAIGN, startedAt }));
    await preflightAll(rows);
    state.phase = 'sending';
    for (const row of rows) {
      state.lastRow = row.r;
      try {
        await sendOne(row);
        state.sent++;
        state.mediaFetched++;
      } catch (e) {
        state.failed++;
        state.phase = 'stopped_on_error';
        state.error = String(e);
        state.completedAt = new Date().toISOString();
        console.error('BULK_STOP', JSON.stringify(state));
        return state;
      }
      await new Promise(r => setTimeout(r, 250));
      if (state.sent % 25 === 0) console.log('SEND_PROGRESS', state.sent, '/', rows.length);
    }
    state.phase = 'complete';
    state.completedAt = new Date().toISOString();
    console.log('BULK_COMPLETE', JSON.stringify(state));
    return state;
  } catch (e) {
    state.phase = 'aborted';
    state.error = String(e);
    state.completedAt = new Date().toISOString();
    console.error('BULK_ABORT', JSON.stringify(state));
    return state;
  } finally {
    running = false;
  }
}

function json(res, obj, status=200) {
  const body = JSON.stringify(obj);
  res.statusCode = status;
  res.setHeader('content-type', 'application/json');
  res.setHeader('content-length', Buffer.byteLength(body));
  res.end(body);
}

function startBulk(res) {
  if (!running && state.phase === 'ready') runBulk().catch(e => console.error('UNHANDLED_BULK_ERROR', String(e)));
  return json(res, { accepted: true, state }, 202);
}

http.createServer((req, res) => {
  const u = new URL(req.url, 'http://localhost');
  if (u.pathname === '/status') return json(res, state);
  if (u.pathname === '/payload-check') {
    let rows = null;
    let error = null;
    try { rows = loadRows(); } catch (e) { error = String(e); }
    return json(res, { diag: payloadDiagnostics(), rowCount: rows?.length || 0, error });
  }
  if (u.pathname === '/preflight-results') {
    const offset = Math.max(0, Number(u.searchParams.get('offset') || 0));
    const limit = Math.min(250, Math.max(1, Number(u.searchParams.get('limit') || 100)));
    return json(res, { total: preflight.length, offset, items: preflight.slice(offset, offset + limit) });
  }
  if (u.pathname === '/results') {
    const offset = Math.max(0, Number(u.searchParams.get('offset') || 0));
    const limit = Math.min(250, Math.max(1, Number(u.searchParams.get('limit') || 100)));
    return json(res, { total: results.length, offset, items: results.slice(offset, offset + limit) });
  }
  if (u.pathname === `/run/${RUN_TOKEN}` || u.pathname === '/execute-praveen-test-7f2c') return startBulk(res);
  return json(res, { error: 'not found' }, 404);
}).listen(port, '0.0.0.0', () => {
  console.log('BULK_SENDER_READY');
  console.log('PAYLOAD_BOOT_DIAG', JSON.stringify(payloadDiagnostics()));
});
