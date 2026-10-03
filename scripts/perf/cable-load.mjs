#!/usr/bin/env node
// Opens N Action Cable sockets against a local API and reports the server's memory and CPU.
//
//   CABLE_TOKEN=<bearer token of a signed-in test user> \
//   node scripts/perf/cable-load.mjs --api http://127.0.0.1:7904 --pid <puma pid> --sockets 500 --hold 30
//
// Each socket gets its own single-use ticket, sent as a WebSocket subprotocol like the app does.
// Tickets come from POST /api/cable/ticket (rate-limited to 30 a minute per user), or, for more
// sockets than that, from --tickets-file (one per line), made on the local server with:
//   bin/rails runner 's = Session.find(ID); 500.times { puts RealtimeTicket.issue(s) }' > tickets.txt Each socket subscribes to UserChannel, then the script holds
// them open for --hold seconds (the server pings every socket every 3 s) and samples the server
// process from /proc (Linux). Run it against a local server only, never production.
import { readFileSync } from 'node:fs';

const args = Object.fromEntries(
  process.argv
    .slice(2)
    .join(' ')
    .split('--')
    .filter(Boolean)
    .map((pair) => pair.trim().split(/\s+/)),
);
const api = args.api ?? 'http://127.0.0.1:7904';
const origin = args.origin ?? 'http://localhost:7900';
const count = Number(args.sockets ?? 500);
const holdSeconds = Number(args.hold ?? 30);
const pid = args.pid;
const token = process.env.CABLE_TOKEN;
if (!token) throw new Error('Set CABLE_TOKEN to a bearer token of a local test user.');

const ticks = 100; // USER_HZ on Linux
function sample() {
  if (!pid) return null;
  const status = readFileSync(`/proc/${pid}/status`, 'utf8');
  const rssKb = Number(status.match(/VmRSS:\s+(\d+)/)[1]);
  const threads = Number(status.match(/Threads:\s+(\d+)/)[1]);
  const stat = readFileSync(`/proc/${pid}/stat`, 'utf8').split(') ')[1].split(' ');
  const cpuSeconds = (Number(stat[11]) + Number(stat[12])) / ticks; // utime + stime
  return { rssMb: rssKb / 1024, threads, cpuSeconds, at: performance.now() };
}

const ticketFile = args['tickets-file'] ? readFileSync(args['tickets-file'], 'utf8').split('\n').filter(Boolean) : null;
const wsBase = api.replace(/^http/, 'ws');
async function ticket() {
  if (ticketFile) return { ticket: ticketFile.pop(), url: `${wsBase}/cable` };
  const response = await fetch(`${api}/api/cable/ticket`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, Origin: origin },
  });
  if (!response.ok) throw new Error(`ticket: HTTP ${response.status}`);
  return response.json();
}
const identifier = JSON.stringify({ channel: 'UserChannel' });

const before = sample();
const started = performance.now();
const latencies = [];
let failed = 0;
let pings = 0;
const sockets = [];
async function openOne() {
  const t0 = performance.now();
  const { ticket: value, url } = await ticket();
  return new Promise((resolve) => {
    const ws = new WebSocket(url, {
      protocols: ['actioncable-v1-json', `musilynk.ticket.${value}`],
      headers: { Origin: origin },
    });
    sockets.push(ws);
    let done = false;
    const finish = (ok) => {
      if (done) return;
      done = true;
      if (ok) latencies.push(performance.now() - t0);
      else failed += 1;
      resolve();
    };
    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === 'welcome') ws.send(JSON.stringify({ command: 'subscribe', identifier }));
      else if (data.type === 'confirm_subscription') finish(true);
      else if (data.type === 'ping') pings += 1;
      else if (data.type === 'reject_subscription' || data.type === 'disconnect') finish(false);
    };
    ws.onerror = () => finish(false);
    ws.onclose = () => finish(false);
    setTimeout(() => finish(false), 20_000);
  });
}
// Open in waves of 50, as a page of real clients would arrive.
for (let i = 0; i < count; i += 50) await Promise.all(Array.from({ length: Math.min(50, count - i) }, openOne));
const connectedAt = performance.now();
const afterConnect = sample();
await new Promise((resolve) => setTimeout(resolve, holdSeconds * 1000));
const afterHold = sample();
sockets.forEach((ws) => ws.close());

const sorted = latencies.sort((a, b) => a - b);
const pct = (p) =>
  sorted.length ? sorted[Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length))].toFixed(0) : '-';
const report = {
  sockets: count,
  subscribed: sorted.length,
  failed,
  openAllSeconds: ((connectedAt - started) / 1000).toFixed(1),
  subscribeMs: { p50: pct(50), p95: pct(95), max: pct(100) },
  pingsReceived: pings,
};
if (before && afterConnect && afterHold) {
  Object.assign(report, {
    serverRssMb: {
      before: before.rssMb.toFixed(0),
      connected: afterConnect.rssMb.toFixed(0),
      afterHold: afterHold.rssMb.toFixed(0),
    },
    perSocketKb: (((afterHold.rssMb - before.rssMb) * 1024) / count).toFixed(1),
    serverThreads: afterHold.threads,
    serverCpuPercentWhileOpening: (
      ((afterConnect.cpuSeconds - before.cpuSeconds) / ((afterConnect.at - before.at) / 1000)) *
      100
    ).toFixed(0),
    serverCpuPercentIdleHold: (
      ((afterHold.cpuSeconds - afterConnect.cpuSeconds) / ((afterHold.at - afterConnect.at) / 1000)) *
      100
    ).toFixed(1),
  });
}
console.log(JSON.stringify(report, null, 2));
process.exit(0);
