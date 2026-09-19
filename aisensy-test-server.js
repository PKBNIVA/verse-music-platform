import http from 'node:http';

const port = process.env.PORT || 10000;
const API_URL = 'https://backend.aisensy.com/campaign/t1/api/v2';
const ROW = 'praveen-test-resend-2';
const MEDIA = 'https://aisensy-media-normalizer.onrender.com/q/praveen-test-resend-2/aHR0cHM6Ly9ldmVudGh1Zy01ZjkwZGJlMzFjODAuaGVyb2t1YXBwLmNvbS8vcmFpbHMvYWN0aXZlX3N0b3JhZ2UvYmxvYnMvcmVkaXJlY3QvZXlKZmNtRnBiSE1pT25zaWJXVnpjMkZuWlNJNklrSkJhSEJCY0VKWklpd2laWGh3SWpwdWRXeHNMQ0p3ZFhJaU9pSmliRzlpWDJsa0luMTktLTMxODkxYWIzYjA5MjFhMTAzZTUxYjI2MWU1MmExMmU1MjgzMzc5ZGIvcXJjb2RlLnBuZw.jpg';
let state = { phase: 'ready', error: null, messageId: null, mediaFetched: false, httpStatus: null };
let running = false;

async function hitCount() {
  const r = await fetch(`https://aisensy-media-normalizer.onrender.com/hit/${ROW}`, { signal: AbortSignal.timeout(15000) });
  const j = await r.json();
  return Number(j.get || 0);
}

async function sendTest() {
  if (running) return state;
  running = true;
  state = { phase: 'preflight', error: null, messageId: null, mediaFetched: false, httpStatus: null };
  try {
    const pf = await fetch(MEDIA, { method: 'HEAD', signal: AbortSignal.timeout(45000) });
    if (!pf.ok || pf.headers.get('content-type') !== 'image/jpeg') throw new Error('media preflight failed');
    const baseline = await hitCount();
    state.phase = 'sending';
    const payload = {
      apiKey: process.env.AISENSY_API_KEY,
      campaignName: 'Praveen Kumar QR API Test',
      destination: '+919804636974',
      userName: 'Praveen Kumar',
      source: 'JLC',
      media: { url: MEDIA, filename: 'qrcode.jpg' },
      templateParams: ['Praveen Kumar']
    };
    const r = await fetch(API_URL, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload), signal: AbortSignal.timeout(45000) });
    const text = await r.text();
    let parsed = null; try { parsed = JSON.parse(text); } catch {}
    state.httpStatus = r.status;
    if (!(r.ok && String(parsed?.success) === 'true' && parsed?.submitted_message_id)) throw new Error(text);
    state.messageId = parsed.submitted_message_id;
    const deadline = Date.now() + 20000;
    while (Date.now() < deadline) {
      await new Promise(r => setTimeout(r, 300));
      if (await hitCount() > baseline) { state.mediaFetched = true; break; }
    }
    if (!state.mediaFetched) throw new Error('media was not fetched by AiSensy');
    state.phase = 'complete';
  } catch (e) {
    state.phase = 'error';
    state.error = String(e);
  } finally { running = false; }
  console.log('TEST_COMPLETE', JSON.stringify(state));
  return state;
}

http.createServer((req, res) => {
  res.setHeader('content-type', 'application/json');
  if (req.url === '/test-praveen-resend') {
    sendTest().catch(()=>{});
    res.statusCode = 202;
    return res.end(JSON.stringify({ accepted: true, state }));
  }
  if (req.url === '/test-status') return res.end(JSON.stringify(state));
  res.statusCode = 404; res.end(JSON.stringify({ error: 'not found' }));
}).listen(port, '0.0.0.0', () => console.log('TEST_SENDER_READY'));
