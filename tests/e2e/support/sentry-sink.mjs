// A stand-in for Sentry's ingest endpoint used by tests/e2e/error-monitoring.spec.ts.
// The QA build's DSN points here (Sentry sends with fetch keepalive, which Playwright
// cannot intercept), so envelopes are recorded locally and never reach a real Sentry.
//   POST /api/<project>/envelope/  records the body
//   GET  /__envelopes              returns every recorded body as a JSON array
import {createServer} from 'node:http';

const port = Number(process.argv[2] || process.env.PORT || 4175);
const envelopes = [];
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': '*',
};

createServer((request, response) => {
  if (request.method === 'OPTIONS') {
    response.writeHead(204, cors);
    return response.end();
  }
  if (request.method === 'POST' && /\/envelope\/?$/.test(new URL(request.url, 'http://sink').pathname)) {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => {
      envelopes.push(Buffer.concat(chunks).toString('utf8'));
      response.writeHead(200, {...cors, 'Content-Type': 'application/json'});
      response.end('{}');
    });
    return;
  }
  if (request.method === 'GET' && request.url.startsWith('/__envelopes')) {
    response.writeHead(200, {...cors, 'Content-Type': 'application/json'});
    return response.end(JSON.stringify(envelopes));
  }
  response.writeHead(200, {...cors, 'Content-Type': 'text/plain'});
  response.end('sentry sink');
}).listen(port, '127.0.0.1');
