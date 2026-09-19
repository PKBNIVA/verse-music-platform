import http from 'node:http';

const port = process.env.PORT || 10000;
let attempted = false;
let lastResult = { status: 'ready' };
const originalQrUrl = 'https://eventhug-5f90dbe31c80.herokuapp.com//rails/active_storage/blobs/redirect/eyJfcmFpbHMiOnsibWVzc2FnZSI6IkJBaHBBcEJZIiwiZXhwIjpudWxsLCJwdXIiOiJibG9iX2lkIn19--31891ab3b0921a103e51b261e52a12e5283379db/qrcode.png';

const payload = {
  apiKey: process.env.AISENSY_API_KEY,
  campaignName: 'Praveen Kumar QR API Test',
  destination: '+919804636974',
  userName: 'Praveen Kumar',
  source: 'JLC',
  media: {
    url: 'https://aisensy-praveen-test.onrender.com/qr.png',
    filename: 'entry_qr.png'
  },
  templateParams: ['Praveen Kumar']
};

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
  } catch (error) {
    lastResult = { status: 'error', error: String(error) };
  }
  return lastResult;
}

http.createServer(async (req, res) => {
  if (req.url === '/qr.png') {
    try {
      const upstream = await fetch(originalQrUrl, { redirect: 'follow' });
      if (!upstream.ok) {
        res.statusCode = upstream.status;
        res.end('QR fetch failed');
        return;
      }
      const body = Buffer.from(await upstream.arrayBuffer());
      res.statusCode = 200;
      res.setHeader('content-type', 'image/png');
      res.setHeader('content-length', String(body.length));
      res.setHeader('cache-control', 'public, max-age=3600');
      res.end(body);
      return;
    } catch (error) {
      res.statusCode = 502;
      res.end('QR proxy error');
      return;
    }
  }

  res.setHeader('content-type', 'application/json');
  if (req.url === '/execute-praveen-test-7f2c') {
    const result = await send();
    res.end(JSON.stringify(result));
    return;
  }
  res.end(JSON.stringify(lastResult));
}).listen(port, '0.0.0.0');
