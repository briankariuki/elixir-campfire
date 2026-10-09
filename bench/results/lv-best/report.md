```
date: 2026-10-07T17:45:37+0000
host: Apple M2 Pro, 10 cores (6 performance + 4 efficiency), 16GB, macOS 26.6.2
host (1): orbstack: Version: 2.1.1 (2010100); VM cpu/memory: cpu: 10 memory_mib: 8192
host (2): power: Now drawing from 'AC Power'  -InternalBattery-0 (id=35192931)	99%; finishing charge; 0:00 remaining present: true; lowpowermode=lowpowermode 0
host (3): host load before: 20:45  up 24 days,  9:32, 3 users, load averages: 1.79 2.01 1.93
linux (where the benchmark runs): 6.19.13-orbstack-gbd1dc07b8cf4 aarch64, cpu model not exposed, 10 vCPUs, 7.8GB (OrbStack VM, harness container)
server cpus: 0-3 (nproc 4; Postgres + app together); loadgen cpus: 4-7; harness cpus: 8-9; network: host
env (app): PORT=47130 PHX_HOST=localhost MIX_ENV=prod (image) TRUST_PROXY_HEADERS=(unset) POOL_SIZE=(default 10) UPLOADS_DIR=/data/uploads APP_EXTRA_ENV=(none) LIVEVIEW_ARGS=(none)
postgres: postgres:17 port 47131 args: (defaults)
seed sha256: e233c542b4a233f4348888cdd21066d4e3549e868da99755518d5383c974967f  campfire.sql
seed sha256: 089726b88abf5f9baf1bb19b2e86beb83d3105ab976d5e6e50f6265cde324d5e  labels.json
seed sha256: 92e368f1640d4a17c6bc83bfb4f731a3426fdaa562f01f8fa0fa1fd5b45bff27  uploads/ (8 files, names+sizes)
source digest: d29e74ecdae2bbd89a0ddcc5247f0e7ac35a22ca (dirty: 12 files, diff sha256 867f1b5560b6)
workload: suites=liveview HTTP_SECS=8 HTTP_CONCS=1 16 64 CABLE_CLIENTS=100 500 1000 CABLE_TPUT_SECS=15 CABLE_POSTERS=4 DISTINCT_CLIENTS=100 500 1000 UPLOAD_REPS=5 IDLE_SECS=10 REPS=2
quiet wait: LOAD_MAX=1.5 LOAD_WAIT_SECS=900
user agent: (none)
campfire image: campfire-port:best sha256:54dcb045cd82fecf15875f5de0711bce02945f7420ea33309f137d26341e17db 2026-10-07T20:42:51.961168082+03:00 unpacked_bytes=261541357
postgres image id: sha256:97432f980da100ebd3e419711efee84e1e97a966d62c035286a07f239ddb4d9c 2026-09-19T00:38:59.786253347Z unpacked_bytes=476570430
loadgen image: campfire-loadgen:bench sha256:35d24d2d7e8d395ce7df23196d5c0c4984caa45e16fe64f305c7abab2f76cef2 2026-10-07T07:57:00.714539169+03:00 unpacked_bytes=101186065
```

Reps: campfire 2. Cells: median [min–max].

### Startup and memory

Memory is the sum of the app and Postgres containers for this port (per-container splits are in the raw JSON).

| Metric | campfire |
|---|---|
| cold start: docker run → /up 200 (ms) | 1,152 [1,152–1,153] |
| idle memory.current (MiB) | 488 [417–559] |
| idle anon (MiB) | 286 [279–293] |
| peak memory.current under load (MiB) | 2,288 [2,201–2,375] |
| peak anon under load (MiB) | 2,151 [2,079–2,223] |

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
| 100 clients: connect+subscribe all (s) | 0.56 [0.55–0.58] |
| 100 clients: paced post→one client p50 ms | 17.9 [17.0–18.7] |
| 100 clients: paced post→all clients p50 ms | 18.5 [17.6–19.5] |
| 100 clients: paced post→all clients p99 ms | 26.0 [23.2–28.8] |
| 100 clients: max sustained msgs/s (delivered to all) | 280 [276–284] |
| 100 clients: deliveries/s (client×message) | 27,994 [27,572–28,417] |
| 100 clients: saturated post→all p50 ms | 15.2 [15.0–15.4] |
| 100 clients: saturated POST p50 ms | 13.7 [13.5–13.9] |
| 500 clients: subscribed | 500 [500–500] |
| 500 clients: connect+subscribe all (s) | 2.48 [2.46–2.49] |
| 500 clients: paced post→one client p50 ms | 24.2 [23.6–24.8] |
| 500 clients: paced post→all clients p50 ms | 26.2 [25.9–26.5] |
| 500 clients: paced post→all clients p99 ms | 41.3 [40.7–42.0] |
| 500 clients: max sustained msgs/s (delivered to all) | 135 [132–137] |
| 500 clients: deliveries/s (client×message) | 67,279 [66,216–68,342] |
| 500 clients: saturated post→all p50 ms | 29.7 [29.3–30.0] |
| 500 clients: saturated POST p50 ms | 29.3 [28.9–29.6] |
| 1000 clients: subscribed | 1,000 [1,000–1,000] |
| 1000 clients: connect+subscribe all (s) | 5.11 [5.09–5.12] |
| 1000 clients: paced post→one client p50 ms | 28.5 [28.4–28.6] |
| 1000 clients: paced post→all clients p50 ms | 34.0 [33.5–34.5] |
| 1000 clients: paced post→all clients p99 ms | 52.3 [47.8–56.7] |
| 1000 clients: max sustained msgs/s (delivered to all) | 80.9 [79.1–82.7] |
| 1000 clients: deliveries/s (client×message) | 80,894 [79,089–82,700] |
| 1000 clients: saturated post→all p50 ms | 48.3 [46.9–49.7] |
| 1000 clients: saturated POST p50 ms | 48.7 [47.5–50.0] |

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
| 100 clients, all subscribed, idle: app process Pss | 529 [518–540] |
| 100 clients, all subscribed, idle: app process RssAnon | 455 [445–465] |
| 100 clients, all subscribed, idle: serving processes Pss | 603 [592–615] |
| 100 clients, all subscribed, idle: whole container Pss | 604 [593–615] |
| 100 clients, saturated fan-out: app process Pss | 538 [527–550] |
| 100 clients, saturated fan-out: app process RssAnon | 464 [454–475] |
| 100 clients, saturated fan-out: serving processes Pss | 620 [607–632] |
| 100 clients, saturated fan-out: whole container Pss | 616 [604–628] |
| 500 clients, all subscribed, idle: app process Pss | 1,185 [1,175–1,195] |
| 500 clients, all subscribed, idle: app process RssAnon | 1,112 [1,102–1,122] |
| 500 clients, all subscribed, idle: serving processes Pss | 1,270 [1,260–1,280] |
| 500 clients, all subscribed, idle: whole container Pss | 1,271 [1,260–1,281] |
| 500 clients, saturated fan-out: app process Pss | 1,265 [1,253–1,278] |
| 500 clients, saturated fan-out: app process RssAnon | 1,196 [1,186–1,205] |
| 500 clients, saturated fan-out: serving processes Pss | 1,352 [1,338–1,366] |
| 500 clients, saturated fan-out: whole container Pss | 1,346 [1,329–1,364] |
| 1000 clients, all subscribed, idle: app process Pss | 2,062 [1,959–2,164] |
| 1000 clients, all subscribed, idle: app process RssAnon | 1,992 [1,886–2,098] |
| 1000 clients, all subscribed, idle: serving processes Pss | 2,144 [2,045–2,242] |
| 1000 clients, all subscribed, idle: whole container Pss | 2,144 [2,046–2,243] |
| 1000 clients, saturated fan-out: app process Pss | 2,181 [2,104–2,257] |
| 1000 clients, saturated fan-out: app process RssAnon | 2,114 [2,038–2,190] |
| 1000 clients, saturated fan-out: serving processes Pss | 2,264 [2,192–2,337] |
| 1000 clients, saturated fan-out: whole container Pss | 2,263 [2,190–2,335] |

### Postgres share of CPU (this port)

`CPU µs/success` above is app + Postgres; the Postgres container's part follows.

| Metric | campfire |
|---|---|

### Background jobs at the end of each rep (Oban)

- campfire rep 1: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
- campfire rep 2: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
