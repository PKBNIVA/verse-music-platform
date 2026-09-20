import http from 'node:http';
import zlib from 'node:zlib';
import crypto from 'node:crypto';

const port = process.env.PORT || 10000;
const API_URL = 'https://backend.aisensy.com/campaign/t1/api/v2';
const CAMPAIGN = 'Praveen Kumar QR API Test';
const NORMALIZER = 'https://aisensy-media-normalizer.onrender.com';
const OLD_EXPECTED_COUNT = 1058;
const OLD_EXPECTED_B64_LENGTH = 54512;
const OLD_EXPECTED_SHA256 = '68657959923ff8afc2943372fdb27e990775c591f3440581b167fb8b17589a02';
const NEW_EXPECTED_COUNT = 12;
const RUN_ID = `${Date.now().toString(36)}-${crypto.randomBytes(4).toString('hex')}`;

function blankState() {
  return { phase: 'ready', total: 0, checked: 0, sent: 0, failed: 0, lastRow: null, error: null, startedAt: null, completedAt: null };
}

const jobs = {
  old: { state: blankState(), running: false, stop: false, results: [] },
  new: { state: blankState(), running: false, stop: false, results: [] }
};

function validateRows(rows, expected, label) {
  if (!Array.isArray(rows) || rows.length !== expected) throw new Error(`${label} count mismatch: ${rows?.length}`);
  const phones = new Set(rows.map(x => x.p));
  const qrs = new Set(rows.map(x => x.q));
  if (phones.size !== rows.length) throw new Error(`${label} duplicate phone detected`);
  if (qrs.size !== rows.length) throw new Error(`${label} duplicate QR detected`);
  for (const x of rows) {
    if (!x.r || !String(x.n || '').trim() || !/^\+91\d{10}$/.test(x.p || '') || !/^https:\/\/eventhug-5f90dbe31c80\.herokuapp\.com\//.test(x.q || '')) {
      throw new Error(`${label} invalid row ${x.r}`);
    }
  }
  return rows;
}

function oldPayloadDiagnostics() {
  const b64 = [1,2,3,4].map(i => process.env[`BULK_DATA_BR_${i}`] || '').join('') || process.env.BULK_DATA_BR || '';
  let decoded = Buffer.alloc(0);
  try { decoded = Buffer.from(b64, 'base64'); } catch {}
  const sha = decoded.length ? crypto.createHash('sha256').update(decoded).digest('hex') : null;
  return { b64Length: b64.length, decodedSha256: sha, lengthOk: b64.length === OLD_EXPECTED_B64_LENGTH, shaOk: sha === OLD_EXPECTED_SHA256 };
}

function loadOldRows() {
  const b64 = [1,2,3,4].map(i => process.env[`BULK_DATA_BR_${i}`] || '').join('') || process.env.BULK_DATA_BR;
  const diag = oldPayloadDiagnostics();
  if (!diag.lengthOk || !diag.shaOk) throw new Error(`old payload integrity mismatch ${JSON.stringify(diag)}`);
  const rows = JSON.parse(zlib.brotliDecompressSync(Buffer.from(b64, 'base64')).toString('utf8'));
  return validateRows(rows, OLD_EXPECTED_COUNT, 'old');
}

function loadNewRows() {
  const b64 = process.env.NEW_DATA_ZLIB_B64 || '';
  if (!b64) throw new Error('new payload missing');
  const rows = JSON.parse(zlib.inflateSync(Buffer.from(b64, 'base64')).toString('utf8'));
  return validateRows(rows, NEW_EXPECTED_COUNT, 'new');
}

function verifySets(oldRows, newRows) {
  const oldPhones = new Set(oldRows.map(x => x.p));
  const overlap = newRows.filter(x => oldPhones.has(x.p));
  if (overlap.length) throw new Error(`new/old phone overlap detected: ${overlap.map(x => x.p).join(',')}`);
}

function mediaUrl(jobName, row) {
  const token = Buffer.from(row.q, 'utf8').toString('base64url');
  return `${NORMALIZER}/q/${jobName}-${row.r}/${token}.jpg?v=${RUN_ID}-${jobName}`;
}

async function verifyAndSend(jobName, row) {
  const job = jobs[jobName];
  const url = mediaUrl(jobName, row);
  const pf = await fetch(url, { method: 'HEAD', signal: AbortSignal.timeout(30000) });
  const type = pf.headers.get('content-type') || '';
  const len = Number(pf.headers.get('content-length') || 0);
  if (!pf.ok || type !== 'image/jpeg' || len < 1000 || len > 5_000_000) {
    throw new Error(`media check failed job=${jobName} row=${row.r} status=${pf.status} type=${type} len=${len}`);
  }
  job.state.checked++;

  const payload = {
    apiKey: process.env.AISENSY_API_KEY,
    campaignName: CAMPAIGN,
    destination: row.p,
    userName: row.n,
    source: 'JLC',
    media: { url, filename: `qr-${jobName}-${row.r}.jpg` },
    templateParams: [row.n]
  };

  const started = new Date().toISOString();
  const r = await fetch(API_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(30000)
  });
  const text = await r.text();
  let parsed = null;
  try { parsed = JSON.parse(text); } catch {}
  const accepted = r.ok && String(parsed?.success) === 'true' && Boolean(parsed?.submitted_message_id);
  const audit = {
    job: jobName,
    sourceRow: row.r,
    name: row.n,
    phone: row.p,
    startedAt: started,
    httpStatus: r.status,
    accepted: Boolean(accepted),
    messageId: parsed?.submitted_message_id || null,
    mediaBytes: len,
    mediaUrlVersion: RUN_ID,
    response: accepted ? 'accepted' : text.slice(0, 300)
  };
  job.results.push(audit);
  console.log('AUDIT', JSON.stringify(audit));
  if (!accepted) throw new Error(`AiSensy rejected job=${jobName} row=${row.r}: ${text}`);

  job.state.sent++;
  job.state.lastRow = row.r;
  if (job.state.sent % 50 === 0 || job.state.sent === job.state.total) {
    console.log('SEND_PROGRESS', JSON.stringify({ job: jobName, sent: job.state.sent, total: job.state.total }));
  }
}

async function runJob(jobName, rows, concurrency) {
  const job = jobs[jobName];
  if (job.running || job.state.phase !== 'ready') return job.state;
  job.running = true;
  job.stop = false;
  job.state = { phase: 'sending', total: rows.length, checked: 0, sent: 0, failed: 0, lastRow: null, error: null, startedAt: new Date().toISOString(), completedAt: null };
  console.log('BULK_START', JSON.stringify({ job: jobName, total: rows.length, campaign: CAMPAIGN, runId: RUN_ID, concurrency }));
  let cursor = 0;
  async function worker() {
    while (!job.stop) {
      const i = cursor++;
      if (i >= rows.length) return;
      const row = rows[i];
      try {
        await verifyAndSend(jobName, row);
      } catch (e) {
        job.stop = true;
        job.state.failed++;
        job.state.phase = 'stopped_on_error';
        job.state.error = String(e);
        job.state.lastRow = row.r;
        console.error('BULK_STOP', JSON.stringify({ job: jobName, ...job.state }));
        return;
      }
    }
  }
  try {
    await Promise.all(Array.from({ length: concurrency }, worker));
    if (!job.stop) {
      job.state.phase = 'complete';
      job.state.completedAt = new Date().toISOString();
      console.log('BULK_COMPLETE', JSON.stringify({ job: jobName, ...job.state }));
    } else {
      job.state.completedAt = new Date().toISOString();
    }
  } finally {
    job.running = false;
  }
  return job.state;
}

async function startAll() {
  const oldRows = loadOldRows();
  const newRows = loadNewRows();
  verifySets(oldRows, newRows);
  console.log('ALL_VALIDATED', JSON.stringify({ old: oldRows.length, new: newRows.length, totalSubmissions: oldRows.length + newRows.length, runId: RUN_ID }));
  runJob('old', oldRows, 6).catch(e => console.error('UNHANDLED_OLD', String(e)));
  runJob('new', newRows, 3).catch(e => console.error('UNHANDLED_NEW', String(e)));
}

function sendJson(res, obj, status = 200) {
  const body = JSON.stringify(obj);
  res.statusCode = status;
  res.setHeader('content-type', 'application/json');
  res.setHeader('content-length', Buffer.byteLength(body));
  res.end(body);
}

http.createServer((req, res) => {
  const u = new URL(req.url, 'http://localhost');
  if (u.pathname === '/status') return sendJson(res, { runId: RUN_ID, old: jobs.old.state, new: jobs.new.state });
  if (u.pathname === '/results') {
    const jobName = u.searchParams.get('job') === 'new' ? 'new' : 'old';
    const offset = Math.max(0, Number(u.searchParams.get('offset') || 0));
    const limit = Math.min(250, Math.max(1, Number(u.searchParams.get('limit') || 100)));
    const arr = jobs[jobName].results;
    return sendJson(res, { job: jobName, total: arr.length, offset, items: arr.slice(offset, offset + limit) });
  }
  if (u.pathname === '/run-all' || u.pathname === '/execute-praveen-test-7f2c') {
    if (jobs.old.state.phase === 'ready' && jobs.new.state.phase === 'ready') {
      try { startAll(); } catch (e) { console.error('START_ALL_ABORT', String(e)); return sendJson(res, { accepted: false, error: String(e) }, 500); }
    }
    return sendJson(res, { accepted: true, runId: RUN_ID, old: jobs.old.state, new: jobs.new.state }, 202);
  }
  return sendJson(res, { error: 'not found' }, 404);
}).listen(port, '0.0.0.0', () => {
  console.log('DUAL_BULK_SENDER_READY', JSON.stringify({ runId: RUN_ID, oldDiag: oldPayloadDiagnostics(), newPayloadPresent: Boolean(process.env.NEW_DATA_ZLIB_B64) }));
});
