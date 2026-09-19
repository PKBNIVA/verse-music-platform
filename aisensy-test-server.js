import http from 'node:http';

const port = process.env.PORT || 10000;
let attempted = false;
let lastResult = { status: 'ready' };

const payload = {
  apiKey: process.env.AISENSY_API_KEY,
  campaignName: 'Praveen Kumar QR API Test',
  destination: '+919804636974',
  userName: 'Praveen Kumar',
  source: 'JLC',
  media: {
    url: 'https://eventhug-5f90dbe31c80.herokuapp.com//rails/active_storage/blobs/redirect/eyJfcmFpbHMiOnsibWVzc2FnZSI6IkJBaHBBcEJZIiwiZXhwIjpudWxsLCJwdXIiOiJibG9iX2lkIn19--31891ab3b0921a103e51b261e52a12e5283379db/qrcode.png',
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
  res.setHeader('content-type', 'application/json');
  if (req.url === '/execute-praveen-test-7f2c') {
    const result = await send();
    res.end(JSON.stringify(result));
    return;
  }
  res.end(JSON.stringify(lastResult));
}).listen(port, '0.0.0.0');
