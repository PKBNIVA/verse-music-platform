import http from 'node:http';
import zlib from 'node:zlib';

const port = process.env.PORT || 10000;
const API_URL = 'https://backend.aisensy.com/campaign/t1/api/v2';
const CAMPAIGN = 'Praveen Kumar QR API Test';
const NORMALIZER = 'https://aisensy-media-normalizer.onrender.com';
const RUN_TOKEN = 'bulk-20260920-jlc-final';
let state = { phase: 'ready', total: 0, preflightPassed: 0, sent: 0, failed: 0, lastRow: null, error: null };
let running = false;

function loadRows() {
  const b64 = process.env.BULK_DATA_BR;
  if (!b64) throw new Error('BULK_DATA_BR missing');
  const json = zlib.brotliDecompressSync(Buffer.from(b64, 'base64')).toString('utf8');
  const rows = JSON.parse(json);
  if (!Array.isArray(rows) || rows.length !== 1058) throw new Error(`recipient count mismatch: ${rows?.length}`);
  const phones = new Set(rows.map(x => x.p));
  const qrs = new Set(rows.map(x => x.q));
  if (phones.size !== rows.length) throw new Error('duplicate phone detected');
  if (qrs.size !== rows.length) throw new Error('duplicate QR detected');
  for (const x of rows) {
    if (!x.r || !x.n || !/^\+91\d{10}$/.test(x.p || '') || !/^https:\/\//.test(x.q || '')) throw new Error(`invalid row ${x.r}`);
  }
  return rows;
}

function mediaUrl(source) {
  const token = Buffer.from(source, 'utf8').toString('base64url');
  return `${NORMALIZER}/q/${token}.jpg`;
}

async function preflightOne(row) {
  const url = mediaUrl(row.q);
  const r = await fetch(url, { method: 'HEAD', signal: AbortSignal.timeout(45000) });
  const type = r.headers.get('content-type') || '';
  const len = Number(r.headers.get('content-length') || 0);
  if (!r.ok || !type.startsWith('image/jpeg') || len < 1000) throw new Error(`media preflight failed row=${row.r} status=${r.status} type=${type} len=${len}`);
  return { url, len };
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
        await preflightOne(row);
        state.preflightPassed++;
        if (state.preflightPassed % 50 === 0) console.log('PREFLIGHT_PROGRESS', state.preflightPassed, '/', rows.length);
      } catch (e) {
        failures.push({ row: row.r, name: row.n, error: String(e) });
        console.error('PREFLIGHT_FAIL', JSON.stringify(failures.at(-1)));
      }
    }
  }
  await Promise.all(Array.from({ length: concurrency }, worker));
  if (failures.length) throw new Error(`preflight failed for ${failures.length} rows; first=${JSON.stringify(failures[0])}`);
  console.log('PREFLIGHT_COMPLETE', rows.length);
}

async function sendOne(row) {
  const payload = {
    apiKey: process.env.AISENSY_API_KEY,
    campaignName: CAMPAIGN,
    destination: row.p,
    userName: row.n,
    source: 'JLC',
    media: { url: mediaUrl(row.q), filename: `qr-${row.r}.jpg` },
    templateParams: [row.n]
  };
  const r = await fetch(API_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(45000)
  });
  const text = await r.text();
  let parsed = null;
  try { parsed = JSON.parse(text); } catch {}
  const ok = r.ok && String(parsed?.success) === 'true' && parsed?.submitted_message_id;
  const audit = { row: row.r, name: row.n, phone: row.p, httpStatus: r.status, ok: Boolean(ok), messageId: parsed?.submitted_message_id || null, response: ok ? 'accepted' : text.slice(0, 500) };
  console.log('AUDIT', JSON.stringify(audit));
  if (!ok) throw new Error(`AiSensy rejected row ${row.r}: ${text}`);
  return audit;
}

async function runBulk() {
  if (running) return state;
  running = true;
  try {
    const rows = loadRows();
    state = { phase: 'loaded', total: rows.length, preflightPassed: 0, sent: 0, failed: 0, lastRow: null, error: null };
    console.log('BULK_START', JSON.stringify({ total: rows.length, campaign: CAMPAIGN }));
    await preflightAll(rows);
    state.phase = 'sending';
    for (const row of rows) {
      state.lastRow = row.r;
      try {
        await sendOne(row);
        state.sent++;
      } catch (e) {
        state.failed++;
        state.phase = 'stopped_on_error';
        state.error = String(e);
        console.error('BULK_STOP', JSON.stringify(state));
        return state;
      }
      await new Promise(r => setTimeout(r, 500));
      if (state.sent % 25 === 0) console.log('SEND_PROGRESS', state.sent, '/', rows.length);
    }
    state.phase = 'complete';
    console.log('BULK_COMPLETE', JSON.stringify(state));
    return state;
  } catch (e) {
    state.phase = 'aborted';
    state.error = String(e);
    console.error('BULK_ABORT', JSON.stringify(state));
    return state;
  } finally {
    running = false;
  }
}

http.createServer(async (req, res) => {
  res.setHeader('content-type', 'application/json');
  if (req.url === '/status') { res.end(JSON.stringify(state)); return; }
  if (req.url === `/run/${RUN_TOKEN}`) { const result = await runBulk(); res.end(JSON.stringify(result)); return; }
  res.statusCode = 404; res.end(JSON.stringify({ error: 'not found' }));
}).listen(port, '0.0.0.0', () => console.log('BULK_SENDER_READY'));
