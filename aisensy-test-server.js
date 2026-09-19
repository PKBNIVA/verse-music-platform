import http from 'node:http';

const port = process.env.PORT || 10000;
let attempted = false;
let lastResult = { status: 'ready' };
let qrCache = null;
let qrDiag = { status: 'not-fetched' };
const originalQrUrl = 'https://eventhug-5f90dbe31c80.herokuapp.com//rails/active_storage/blobs/redirect/eyJfcmFpbHMiOnsibWVzc2FnZSI6IkJBaHBBcEJZIiwiZXhwIjpudWxsLCJwdXIiOiJibG9iX2lkIn19--31891ab3b0921a103e51b261e52a12e5283379db/qrcode.png';

const payload = {
  apiKey: process.env.AISENSY_API_KEY,
  campaignName: 'Praveen Kumar QR API Test',
  destination: '+919804636974',
  userName: 'Praveen Kumar',
  source: 'JLC',
  media: {
    url: 'https://aisensy-media-normalizer.onrender.com/qr.jpg',
    filename: 'qrcode.jpg'
  },
  templateParams: ['Praveen Kumar']
};

async function fetchQr() {
  try {
    const upstream = await fetch(originalQrUrl, { redirect: 'follow' });
    const body = Buffer.from(await upstream.arrayBuffer());
    const sig = body.subarray(0, 8).toString('hex');
    qrCache = upstream.ok ? body : null;
    qrDiag = {
      status: upstream.status,
      ok: upstream.ok,
      finalUrl: upstream.url,
      contentType: upstream.headers.get('content-type'),
      contentLengthHeader: upstream.headers.get('content-length'),
      bytes: body.length,
      pngSignature: sig,
      isPng: sig === '89504e470d0a1a0a'
    };
    console.log('QR_DIAG', JSON.stringify(qrDiag));
  } catch (error) {
    qrDiag = { status: 'error', error: String(error) };
    console.error('QR_DIAG', JSON.stringify(qrDiag));
  }
}

async function send() {
  if (attempted) return lastResult;
  attempted = true;
  try {
    const response = await fetch('https://backend.aisensy.com/campaign/t1/api/v2', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const text = await response.text();
    lastResult = { status: 'attempted', httpStatus: response.status, body: text };
    console.log('SEND_RESULT', JSON.stringify(lastResult));
  } catch (error) {
    lastResult = { status: 'error', error: String(error) };
    console.error('SEND_RESULT', JSON.stringify(lastResult));
  }
  return lastResult;
}

await fetchQr();

http.createServer(async (req, res) => {
  if (req.url === '/qr.png') {
    console.log('QR_PROXY_HIT', req.method, req.headers['user-agent'] || 'no-ua');
    if (!qrCache) await fetchQr();
    if (!qrCache) {
      res.statusCode = 502;
      res.end('QR unavailable');
      return;
    }
    res.statusCode = 200;
    res.setHeader('content-type', 'image/png');
    res.setHeader('content-length', String(qrCache.length));
    res.setHeader('content-disposition', 'inline; filename="qrcode.png"');
    res.setHeader('cache-control', 'public, max-age=86400');
    if (req.method === 'HEAD') {
      res.end();
      return;
    }
    res.end(qrCache);
    return;
  }

  res.setHeader('content-type', 'application/json');
  if (req.url === '/diag') {
    res.end(JSON.stringify(qrDiag));
    return;
  }
  if (req.url === '/execute-praveen-test-7f2c') {
    const result = await send();
    res.end(JSON.stringify(result));
    return;
  }
  res.end(JSON.stringify({ lastResult, qrDiag }));
}).listen(port, '0.0.0.0');
