# Real-time updates (Action Cable)

New messages, unread badges and urgent-request progress reach open pages over a WebSocket at
`wss://<api host>/cable`. Polling stays as the fallback: while a page's socket is connected its
polls slow to every 30 s; when the socket drops they return at once to 3 s (open thread), 10 s
(inbox and badges) and 4 s / 15 s (urgent request page).

## How it works

- `POST /api/cable/ticket` (signed in, 30 per minute) returns a signed, single-use ticket valid for
  60 s that names the caller's session. The browser sends it as a WebSocket subprotocol
  (`musilynk.ticket.<ticket>`), never in the URL, so it is not logged (`ticket` is also a filtered
  parameter). The server checks the ticket, that it was not used before (a one-time id in the
  shared cache), and that the session is still active.
- Signing out, a password change or reset, an admin suspension or session revoke, a report action
  that revokes sessions, and account deletion close that session's (or user's) open sockets
  (`Session.revoke!`, `Realtime.disconnect`).
- Channels (`backend/app/channels`): `UserChannel` (the user's own badge hints),
  `ConversationChannel` (the two participants only, and not while either has blocked the other), `UrgentRequestChannel` (the requester only).
  Anyone else's subscription is rejected.
- Broadcasts carry ids and states only (`{ type: "message", id, conversationId }`); pages refetch
  from the usual endpoints, so who may see what is decided there. They are sent after the write
  commits (`Realtime`), and a failed broadcast never fails the write.
- Sockets are accepted only from `ALLOWED_ORIGINS` and `ADMIN_ORIGIN` (the same lists as CORS).
- The Vercel CSP allows `wss://musilynk-api-production.up.railway.app` in `connect-src`.

## Adapter: Solid Cable (default) or Redis

`backend/config/cable.yml` picks the adapter per process:

- **No `REDIS_URL` (today)**: Solid Cable on the existing Postgres. Broadcasts are rows in
  `solid_cable_messages`; each API process polls the table every 0.1 s and rows older than 24 h are
  trimmed. No new service is needed. The web and worker services must use the same database
  (they do), because jobs broadcast too.
- **With `REDIS_URL`**: Redis pub/sub (the same variable the cache already uses). To switch, add a
  Redis service in Railway and set `REDIS_URL` on both `musilynk-api` and `musilynk-worker`
  (Railway variable reference to the Redis service's URL). Redeploy both. Nothing else changes; the
  `solid_cable_messages` table simply stops being written.

Tuning lives in `backend/config/realtime.yml` (ticket lifetime, ticket rate limit, Action Cable
worker threads, Solid Cable polling and retention). Action Cable's worker threads and Solid
Cable's listener are counted in the database pool (`backend/config/database.yml`); sockets do not
hold Puma threads after the upgrade.

## Capacity (measured)

`scripts/perf/cable-load.mjs` opens N sockets against a local API and samples its memory and CPU.
On the 4-vCPU test bed (one Puma process, development mode, Solid Cable, single-use tickets sent as
subprotocols): 500 sockets subscribed with 0 failures in 12.7 s (subscribe p50 714 ms, p95
1,275 ms); server memory 114 → 170 MB (about 115 kB per socket); about 5.5% of one CPU while
holding them (Action Cable pings every socket every 3 s).

## Turning it off

Set `CABLE_ENABLED=false` on the `musilynk-api` service in Railway (Variables; a restart, no
deploy). `GET /me` and sign-in then say `realtime: false`, pages stop asking for tickets and poll at
their old pace, and `POST /api/cable/ticket` answers 503 `REALTIME_DISABLED`. Remove the variable
(or set `true`) to turn it back on; without it, `enabled` in `backend/config/realtime.yml` decides.

Independently of the switch, if `/cable` is unreachable (or `POST /api/cable/ticket` fails) the app
keeps polling at the old intervals and retries the socket with backoff (1 s doubling to 30 s).
To remove it entirely, revert the release; the `solid_cable_messages` table can stay.

## Environment variables

`CABLE_ENABLED` (new, optional, `musilynk-api`): `true`/`false` overrides `enabled` in
`config/realtime.yml`; unset means the config decides (on). `REDIS_URL` (optional, existing) switches the adapter; `ALLOWED_ORIGINS` and
`ADMIN_ORIGIN` (existing) gate socket origins.
