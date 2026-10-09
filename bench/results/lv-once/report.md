```
date: 2026-10-07T17:25:48+0000
host: Apple M2 Pro, 10 cores (6 performance + 4 efficiency), 16GB, macOS 26.6.2
host (1): orbstack: Version: 2.1.1 (2010100); VM cpu/memory: cpu: 10 memory_mib: 8192
host (2): power: Now drawing from 'AC Power'  -InternalBattery-0 (id=35192931)	99%; finishing charge; 0:05 remaining present: true; lowpowermode=lowpowermode 0
host (3): host load before: 20:25  up 24 days,  9:12, 3 users, load averages: 2.46 1.93 1.80
linux (where the benchmark runs): 6.19.13-orbstack-gbd1dc07b8cf4 aarch64, cpu model not exposed, 10 vCPUs, 7.8GB (OrbStack VM, harness container)
server cpus: 0-3 (nproc 4; Postgres + app together); loadgen cpus: 4-7; harness cpus: 8-9; network: host
env (app): PORT=47130 PHX_HOST=localhost MIX_ENV=prod (image) TRUST_PROXY_HEADERS=(unset) POOL_SIZE=(default 10) UPLOADS_DIR=/data/uploads APP_EXTRA_ENV=(none) LIVEVIEW_ARGS=(none)
postgres: postgres:17 port 47131 args: (defaults)
seed sha256: e233c542b4a233f4348888cdd21066d4e3549e868da99755518d5383c974967f  campfire.sql
seed sha256: 089726b88abf5f9baf1bb19b2e86beb83d3105ab976d5e6e50f6265cde324d5e  labels.json
seed sha256: 92e368f1640d4a17c6bc83bfb4f731a3426fdaa562f01f8fa0fa1fd5b45bff27  uploads/ (8 files, names+sizes)
source digest: d29e74ecdae2bbd89a0ddcc5247f0e7ac35a22ca (dirty: 10 files, diff sha256 ad0e5a0a1c6c)
workload: suites=liveview HTTP_SECS=8 HTTP_CONCS=1 16 64 CABLE_CLIENTS=100 500 1000 CABLE_TPUT_SECS=15 CABLE_POSTERS=4 DISTINCT_CLIENTS=100 500 1000 UPLOAD_REPS=5 IDLE_SECS=10 REPS=2
quiet wait: LOAD_MAX=1.5 LOAD_WAIT_SECS=900
user agent: (none)
campfire image: campfire-port:once sha256:a7f07bdaff210f334c51da36cc4fb26376934f86e3f190c5db40c36347c89bc3 2026-10-07T20:25:13.677435977+03:00 unpacked_bytes=261540813
postgres image id: sha256:97432f980da100ebd3e419711efee84e1e97a966d62c035286a07f239ddb4d9c 2026-09-19T00:38:59.786253347Z unpacked_bytes=476570430
loadgen image: campfire-loadgen:bench sha256:35d24d2d7e8d395ce7df23196d5c0c4984caa45e16fe64f305c7abab2f76cef2 2026-10-07T07:57:00.714539169+03:00 unpacked_bytes=101186065
```

Reps: campfire 2. Cells: median [min–max].

### Startup and memory

Memory is the sum of the app and Postgres containers for this port (per-container splits are in the raw JSON).

| Metric | campfire |
|---|---|
| cold start: docker run → /up 200 (ms) | 1,209 [1,173–1,245] |
| idle memory.current (MiB) | 519 [518–520] |
| idle anon (MiB) | 292 [291–293] |
| peak memory.current under load (MiB) | 2,282 [2,263–2,301] |
| peak anon under load (MiB) | 2,156 [2,117–2,196] |

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
| 100 clients: connect+subscribe all (s) | 0.55 [0.53–0.56] |
| 100 clients: paced post→one client p50 ms | 19.2 [19.2–19.3] |
| 100 clients: paced post→all clients p50 ms | 20.4 [20.3–20.5] |
| 100 clients: paced post→all clients p99 ms | 26.4 [25.8–27.0] |
| 100 clients: max sustained msgs/s (delivered to all) | 276 [275–277] |
| 100 clients: deliveries/s (client×message) | 27,602 [27,531–27,674] |
| 100 clients: saturated post→all p50 ms | 15.4 [15.3–15.4] |
| 100 clients: saturated POST p50 ms | 14.0 [13.9–14.0] |
| 500 clients: subscribed | 500 [500–500] |
| 500 clients: connect+subscribe all (s) | 2.42 [2.34–2.49] |
| 500 clients: paced post→one client p50 ms | 24.5 [24.2–24.9] |
| 500 clients: paced post→all clients p50 ms | 26.6 [26.4–26.8] |
| 500 clients: paced post→all clients p99 ms | 35.9 [34.0–37.7] |
| 500 clients: max sustained msgs/s (delivered to all) | 126 [124–127] |
| 500 clients: deliveries/s (client×message) | 62,784 [62,263–63,306] |
| 500 clients: saturated post→all p50 ms | 31.7 [31.3–32.1] |
| 500 clients: saturated POST p50 ms | 31.4 [31.1–31.7] |
| 1000 clients: subscribed | 1,000 [1,000–1,000] |
| 1000 clients: connect+subscribe all (s) | 5.01 [5.00–5.02] |
| 1000 clients: paced post→one client p50 ms | 31.0 [31.0–31.1] |
| 1000 clients: paced post→all clients p50 ms | 36.1 [35.4–36.9] |
| 1000 clients: paced post→all clients p99 ms | 46.5 [45.7–47.2] |
| 1000 clients: max sustained msgs/s (delivered to all) | 74.5 [73.0–76.0] |
| 1000 clients: deliveries/s (client×message) | 74,458 [72,950–75,965] |
| 1000 clients: saturated post→all p50 ms | 52.7 [51.8–53.7] |
| 1000 clients: saturated POST p50 ms | 52.8 [51.8–53.8] |

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
| 100 clients, all subscribed, idle: app process Pss | 535 [533–538] |
| 100 clients, all subscribed, idle: app process RssAnon | 461 [458–463] |
| 100 clients, all subscribed, idle: serving processes Pss | 610 [608–613] |
| 100 clients, all subscribed, idle: whole container Pss | 611 [609–613] |
| 100 clients, saturated fan-out: app process Pss | 540 [535–544] |
| 100 clients, saturated fan-out: app process RssAnon | 465 [461–470] |
| 100 clients, saturated fan-out: serving processes Pss | 620 [616–625] |
| 100 clients, saturated fan-out: whole container Pss | 619 [614–623] |
| 500 clients, all subscribed, idle: app process Pss | 1,219 [1,195–1,243] |
| 500 clients, all subscribed, idle: app process RssAnon | 1,145 [1,121–1,170] |
| 500 clients, all subscribed, idle: serving processes Pss | 1,305 [1,280–1,330] |
| 500 clients, all subscribed, idle: whole container Pss | 1,305 [1,281–1,330] |
| 500 clients, saturated fan-out: app process Pss | 1,294 [1,287–1,300] |
| 500 clients, saturated fan-out: app process RssAnon | 1,220 [1,215–1,226] |
| 500 clients, saturated fan-out: serving processes Pss | 1,380 [1,373–1,387] |
| 500 clients, saturated fan-out: whole container Pss | 1,379 [1,372–1,386] |
| 1000 clients, all subscribed, idle: app process Pss | 2,040 [1,972–2,109] |
| 1000 clients, all subscribed, idle: app process RssAnon | 1,971 [1,899–2,042] |
| 1000 clients, all subscribed, idle: serving processes Pss | 2,127 [2,058–2,196] |
| 1000 clients, all subscribed, idle: whole container Pss | 2,127 [2,058–2,196] |
| 1000 clients, saturated fan-out: app process Pss | 2,182 [2,129–2,235] |
| 1000 clients, saturated fan-out: app process RssAnon | 2,112 [2,056–2,168] |
| 1000 clients, saturated fan-out: serving processes Pss | 2,269 [2,217–2,322] |
| 1000 clients, saturated fan-out: whole container Pss | 2,269 [2,216–2,322] |

### Postgres share of CPU (this port)

`CPU µs/success` above is app + Postgres; the Postgres container's part follows.

| Metric | campfire |
|---|---|

### Background jobs at the end of each rep (Oban)

- campfire rep 1: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
- campfire rep 2: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
