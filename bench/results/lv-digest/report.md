```
date: 2026-10-07T17:11:14+0000
host: Apple M2 Pro, 10 cores (6 performance + 4 efficiency), 16GB, macOS 26.6.2
host (1): orbstack: Version: 2.1.1 (2010100); VM cpu/memory: cpu: 10 memory_mib: 8192
host (2): power: Now drawing from 'AC Power'  -InternalBattery-0 (id=35192931)	95%; charging; 0:25 remaining present: true; lowpowermode=lowpowermode 0
host (3): host load before: 20:11  up 24 days,  8:57, 3 users, load averages: 1.64 1.54 1.88
linux (where the benchmark runs): 6.19.13-orbstack-gbd1dc07b8cf4 aarch64, cpu model not exposed, 10 vCPUs, 7.8GB (OrbStack VM, harness container)
server cpus: 0-3 (nproc 4; Postgres + app together); loadgen cpus: 4-7; harness cpus: 8-9; network: host
env (app): PORT=47130 PHX_HOST=localhost MIX_ENV=prod (image) TRUST_PROXY_HEADERS=(unset) POOL_SIZE=(default 10) UPLOADS_DIR=/data/uploads APP_EXTRA_ENV=(none) LIVEVIEW_ARGS=(none)
postgres: postgres:17 port 47131 args: (defaults)
seed sha256: e233c542b4a233f4348888cdd21066d4e3549e868da99755518d5383c974967f  campfire.sql
seed sha256: 089726b88abf5f9baf1bb19b2e86beb83d3105ab976d5e6e50f6265cde324d5e  labels.json
seed sha256: 92e368f1640d4a17c6bc83bfb4f731a3426fdaa562f01f8fa0fa1fd5b45bff27  uploads/ (8 files, names+sizes)
source digest: d29e74ecdae2bbd89a0ddcc5247f0e7ac35a22ca (dirty: 10 files, diff sha256 b67031b15c37)
workload: suites=liveview HTTP_SECS=8 HTTP_CONCS=1 16 64 CABLE_CLIENTS=100 500 1000 CABLE_TPUT_SECS=15 CABLE_POSTERS=4 DISTINCT_CLIENTS=100 500 1000 UPLOAD_REPS=5 IDLE_SECS=10 REPS=2
quiet wait: LOAD_MAX=1.5 LOAD_WAIT_SECS=900
user agent: (none)
campfire image: campfire-port:digest sha256:8cf3f7346781d3ca2c79915b6269fbbb85ca75a70454bed6d1bfdb10c2719fd2 2026-10-07T20:10:37.591319098+03:00 unpacked_bytes=261540337
postgres image id: sha256:97432f980da100ebd3e419711efee84e1e97a966d62c035286a07f239ddb4d9c 2026-09-19T00:38:59.786253347Z unpacked_bytes=476570430
loadgen image: campfire-loadgen:bench sha256:35d24d2d7e8d395ce7df23196d5c0c4984caa45e16fe64f305c7abab2f76cef2 2026-10-07T07:57:00.714539169+03:00 unpacked_bytes=101186065
```

Reps: campfire 2. Cells: median [min–max].

### Startup and memory

Memory is the sum of the app and Postgres containers for this port (per-container splits are in the raw JSON).

| Metric | campfire |
|---|---|
| cold start: docker run → /up 200 (ms) | 1,174 [1,137–1,212] |
| idle memory.current (MiB) | 494 [433–555] |
| idle anon (MiB) | 289 [288–290] |
| peak memory.current under load (MiB) | 2,312 [2,310–2,314] |
| peak anon under load (MiB) | 2,169 [2,163–2,175] |

### HTTP (signed in; keep-alive; c = concurrent connections)

Signed in as David for session routes; `messages_page` and `post_message` use the bot API (no session).

| Metric | campfire |
|---|---|

### HTTP errors / non-2xx-3xx (first rep, per app)

- campfire: none
- skipped workload `sidebar`: no HTTP endpoint in this app: LiveView renders the sidebar inside the page/socket

### LiveView fan-out, one room, one signed-in user (upstream columns: Action Cable, chatter.js subscriptions per client)

| Metric | campfire |
|---|---|
| 100 clients: subscribed | 100 [100–100] |
| 100 clients: connect+subscribe all (s) | 0.53 [0.53–0.53] |
| 100 clients: paced post→one client p50 ms | 19.8 [19.2–20.3] |
| 100 clients: paced post→all clients p50 ms | 20.6 [19.9–21.4] |
| 100 clients: paced post→all clients p99 ms | 27.6 [26.1–29.0] |
| 100 clients: max sustained msgs/s (delivered to all) | 214 [214–215] |
| 100 clients: deliveries/s (client×message) | 21,422 [21,376–21,468] |
| 100 clients: saturated post→all p50 ms | 18.2 [18.2–18.3] |
| 100 clients: saturated POST p50 ms | 18.3 [18.2–18.3] |
| 500 clients: subscribed | 500 [500–500] |
| 500 clients: connect+subscribe all (s) | 2.46 [2.42–2.51] |
| 500 clients: paced post→one client p50 ms | 26.8 [26.4–27.3] |
| 500 clients: paced post→all clients p50 ms | 28.4 [27.6–29.1] |
| 500 clients: paced post→all clients p99 ms | 48.8 [46.4–51.1] |
| 500 clients: max sustained msgs/s (delivered to all) | 80.2 [78.9–81.5] |
| 500 clients: deliveries/s (client×message) | 40,108 [39,458–40,757] |
| 500 clients: saturated post→all p50 ms | 48.9 [47.7–50.0] |
| 500 clients: saturated POST p50 ms | 48.6 [47.5–49.7] |
| 1000 clients: subscribed | 1,000 [1,000–1,000] |
| 1000 clients: connect+subscribe all (s) | 5.02 [4.98–5.06] |
| 1000 clients: paced post→one client p50 ms | 32.5 [31.2–33.8] |
| 1000 clients: paced post→all clients p50 ms | 38.1 [36.8–39.4] |
| 1000 clients: paced post→all clients p99 ms | 72.6 [59.2–85.9] |
| 1000 clients: max sustained msgs/s (delivered to all) | 51.9 [51.7–52.0] |
| 1000 clients: deliveries/s (client×message) | 51,871 [51,735–52,007] |
| 1000 clients: saturated post→all p50 ms | 73.3 [73.2–73.4] |
| 1000 clients: saturated POST p50 ms | 75.4 [75.3–75.5] |

### Upload + thumbnail (black_hole.jpg, 505 KB)

| Metric | campfire |
|---|---|
| POST with attachment (ms) | – |
| then GET thumb → 200 (ms) | – |
| POST → thumbnail served (ms) | – |

### Memory during fan-out, by process (MiB, peak within the phase)

App process: this port's BEAM; Rails Puma; Elixir's BEAM; Go/Rust's integrated process. Serving totals add Postgres (this port)
or Redis, native helpers and Thruster (upstream). PSS apportions shared pages; RssAnon counts them in each process.

| Metric | campfire |
|---|---|
| 100 clients, all subscribed, idle: app process Pss | 535 [534–536] |
| 100 clients, all subscribed, idle: app process RssAnon | 461 [460–463] |
| 100 clients, all subscribed, idle: serving processes Pss | 610 [610–610] |
| 100 clients, all subscribed, idle: whole container Pss | 610 [610–610] |
| 100 clients, saturated fan-out: app process Pss | 542 [541–543] |
| 100 clients, saturated fan-out: app process RssAnon | 468 [467–470] |
| 100 clients, saturated fan-out: serving processes Pss | 623 [621–625] |
| 100 clients, saturated fan-out: whole container Pss | 620 [620–621] |
| 500 clients, all subscribed, idle: app process Pss | 1,209 [1,201–1,217] |
| 500 clients, all subscribed, idle: app process RssAnon | 1,135 [1,128–1,143] |
| 500 clients, all subscribed, idle: serving processes Pss | 1,294 [1,285–1,303] |
| 500 clients, all subscribed, idle: whole container Pss | 1,294 [1,286–1,303] |
| 500 clients, saturated fan-out: app process Pss | 1,320 [1,300–1,339] |
| 500 clients, saturated fan-out: app process RssAnon | 1,246 [1,227–1,265] |
| 500 clients, saturated fan-out: serving processes Pss | 1,406 [1,387–1,425] |
| 500 clients, saturated fan-out: whole container Pss | 1,405 [1,385–1,425] |
| 1000 clients, all subscribed, idle: app process Pss | 1,984 [1,961–2,006] |
| 1000 clients, all subscribed, idle: app process RssAnon | 1,917 [1,894–1,940] |
| 1000 clients, all subscribed, idle: serving processes Pss | 2,067 [2,043–2,092] |
| 1000 clients, all subscribed, idle: whole container Pss | 2,068 [2,043–2,093] |
| 1000 clients, saturated fan-out: app process Pss | 2,178 [2,174–2,182] |
| 1000 clients, saturated fan-out: app process RssAnon | 2,111 [2,107–2,116] |
| 1000 clients, saturated fan-out: serving processes Pss | 2,264 [2,257–2,270] |
| 1000 clients, saturated fan-out: whole container Pss | 2,262 [2,256–2,269] |

### Postgres share of CPU (this port)

`CPU µs/success` above is app + Postgres; the Postgres container's part follows.

| Metric | campfire |
|---|---|

### Background jobs at the end of each rep (Oban)

- campfire rep 1: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
- campfire rep 2: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
