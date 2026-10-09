```
date: 2026-10-07T17:00:14+0000
host: Apple M2 Pro, 10 cores (6 performance + 4 efficiency), 16GB, macOS 26.6.2
host (1): orbstack: Version: 2.1.1 (2010100); VM cpu/memory: cpu: 10 memory_mib: 8192
host (2): power: Now drawing from 'AC Power'  -InternalBattery-0 (id=35192931)	88%; charging; 0:42 remaining present: true; lowpowermode=lowpowermode 0
host (3): host load before: 20:00  up 24 days,  8:46, 3 users, load averages: 2.14 2.09 2.35
linux (where the benchmark runs): 6.19.13-orbstack-gbd1dc07b8cf4 aarch64, cpu model not exposed, 10 vCPUs, 7.8GB (OrbStack VM, harness container)
server cpus: 0-3 (nproc 4; Postgres + app together); loadgen cpus: 4-7; harness cpus: 8-9; network: host
env (app): PORT=47130 PHX_HOST=localhost MIX_ENV=prod (image) TRUST_PROXY_HEADERS=(unset) POOL_SIZE=(default 10) UPLOADS_DIR=/data/uploads APP_EXTRA_ENV=(none) LIVEVIEW_ARGS=(none)
postgres: postgres:17 port 47131 args: (defaults)
seed sha256: e233c542b4a233f4348888cdd21066d4e3549e868da99755518d5383c974967f  campfire.sql
seed sha256: 089726b88abf5f9baf1bb19b2e86beb83d3105ab976d5e6e50f6265cde324d5e  labels.json
seed sha256: 92e368f1640d4a17c6bc83bfb4f731a3426fdaa562f01f8fa0fa1fd5b45bff27  uploads/ (8 files, names+sizes)
source digest: d29e74ecdae2bbd89a0ddcc5247f0e7ac35a22ca (dirty: 10 files, diff sha256 75bfe967dd81)
workload: suites=liveview HTTP_SECS=8 HTTP_CONCS=1 16 64 CABLE_CLIENTS=100 500 1000 CABLE_TPUT_SECS=15 CABLE_POSTERS=4 DISTINCT_CLIENTS=100 500 1000 UPLOAD_REPS=5 IDLE_SECS=10 REPS=2
quiet wait: LOAD_MAX=1.5 LOAD_WAIT_SECS=900
user agent: (none)
campfire image: campfire-port:html sha256:47e437cffc08accc7e256157e56d6ce5a5e51724375a4ca978e73f24489ad6db 2026-10-07T19:59:36.80009436+03:00 unpacked_bytes=261539833
postgres image id: sha256:97432f980da100ebd3e419711efee84e1e97a966d62c035286a07f239ddb4d9c 2026-09-19T00:38:59.786253347Z unpacked_bytes=476570430
loadgen image: campfire-loadgen:bench sha256:35d24d2d7e8d395ce7df23196d5c0c4984caa45e16fe64f305c7abab2f76cef2 2026-10-07T07:57:00.714539169+03:00 unpacked_bytes=101186065
```

Reps: campfire 2. Cells: median [min–max].

### Startup and memory

Memory is the sum of the app and Postgres containers for this port (per-container splits are in the raw JSON).

| Metric | campfire |
|---|---|
| cold start: docker run → /up 200 (ms) | 1,260 [1,244–1,275] |
| idle memory.current (MiB) | 497 [465–529] |
| idle anon (MiB) | 290 [281–299] |
| peak memory.current under load (MiB) | 2,370 [2,297–2,442] |
| peak anon under load (MiB) | 2,198 [2,127–2,269] |

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
| 100 clients: connect+subscribe all (s) | 0.53 [0.51–0.54] |
| 100 clients: paced post→one client p50 ms | 19.1 [18.0–20.3] |
| 100 clients: paced post→all clients p50 ms | 19.8 [18.6–20.9] |
| 100 clients: paced post→all clients p99 ms | 38.4 [34.9–41.8] |
| 100 clients: max sustained msgs/s (delivered to all) | 202 [201–204] |
| 100 clients: deliveries/s (client×message) | 20,238 [20,123–20,353] |
| 100 clients: saturated post→all p50 ms | 19.2 [19.2–19.3] |
| 100 clients: saturated POST p50 ms | 19.2 [19.2–19.3] |
| 500 clients: subscribed | 500 [500–500] |
| 500 clients: connect+subscribe all (s) | 2.51 [2.48–2.54] |
| 500 clients: paced post→one client p50 ms | 28.0 [27.9–28.1] |
| 500 clients: paced post→all clients p50 ms | 30.8 [30.4–31.3] |
| 500 clients: paced post→all clients p99 ms | 54.6 [46.7–62.5] |
| 500 clients: max sustained msgs/s (delivered to all) | 74.5 [74.3–74.7] |
| 500 clients: deliveries/s (client×message) | 37,242 [37,145–37,339] |
| 500 clients: saturated post→all p50 ms | 52.6 [52.5–52.7] |
| 500 clients: saturated POST p50 ms | 52.6 [52.4–52.8] |
| 1000 clients: subscribed | 1,000 [1,000–1,000] |
| 1000 clients: connect+subscribe all (s) | 5.10 [5.07–5.13] |
| 1000 clients: paced post→one client p50 ms | 34.4 [33.0–35.9] |
| 1000 clients: paced post→all clients p50 ms | 39.5 [38.0–41.1] |
| 1000 clients: paced post→all clients p99 ms | 61.2 [60.2–62.1] |
| 1000 clients: max sustained msgs/s (delivered to all) | 43.5 [43.4–43.6] |
| 1000 clients: deliveries/s (client×message) | 43,502 [43,413–43,592] |
| 1000 clients: saturated post→all p50 ms | 88.7 [88.4–88.9] |
| 1000 clients: saturated POST p50 ms | 90.0 [89.8–90.2] |

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
| 100 clients, all subscribed, idle: app process Pss | 531 [518–544] |
| 100 clients, all subscribed, idle: app process RssAnon | 457 [444–470] |
| 100 clients, all subscribed, idle: serving processes Pss | 606 [593–619] |
| 100 clients, all subscribed, idle: whole container Pss | 606 [593–620] |
| 100 clients, saturated fan-out: app process Pss | 543 [530–557] |
| 100 clients, saturated fan-out: app process RssAnon | 469 [456–482] |
| 100 clients, saturated fan-out: serving processes Pss | 623 [610–637] |
| 100 clients, saturated fan-out: whole container Pss | 622 [608–636] |
| 500 clients, all subscribed, idle: app process Pss | 1,262 [1,202–1,322] |
| 500 clients, all subscribed, idle: app process RssAnon | 1,189 [1,129–1,249] |
| 500 clients, all subscribed, idle: serving processes Pss | 1,347 [1,288–1,407] |
| 500 clients, all subscribed, idle: whole container Pss | 1,348 [1,288–1,408] |
| 500 clients, saturated fan-out: app process Pss | 1,328 [1,289–1,368] |
| 500 clients, saturated fan-out: app process RssAnon | 1,255 [1,216–1,294] |
| 500 clients, saturated fan-out: serving processes Pss | 1,414 [1,376–1,453] |
| 500 clients, saturated fan-out: whole container Pss | 1,414 [1,374–1,453] |
| 1000 clients, all subscribed, idle: app process Pss | 2,077 [1,969–2,184] |
| 1000 clients, all subscribed, idle: app process RssAnon | 2,003 [1,896–2,110] |
| 1000 clients, all subscribed, idle: serving processes Pss | 2,162 [2,055–2,269] |
| 1000 clients, all subscribed, idle: whole container Pss | 2,162 [2,055–2,270] |
| 1000 clients, saturated fan-out: app process Pss | 2,220 [2,144–2,296] |
| 1000 clients, saturated fan-out: app process RssAnon | 2,147 [2,072–2,223] |
| 1000 clients, saturated fan-out: serving processes Pss | 2,307 [2,232–2,382] |
| 1000 clients, saturated fan-out: whole container Pss | 2,306 [2,230–2,382] |

### Postgres share of CPU (this port)

`CPU µs/success` above is app + Postgres; the Postgres container's part follows.

| Metric | campfire |
|---|---|

### Background jobs at the end of each rep (Oban)

- campfire rep 1: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
- campfire rep 2: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
