```
date: 2026-10-07T18:02:28+0000
host: Apple M2 Pro, 10 cores (6 performance + 4 efficiency), 16GB, macOS 26.6.2
host (1): orbstack: Version: 2.1.1 (2010100); VM cpu/memory: cpu: 10 memory_mib: 8192
host (2): power: Now drawing from 'AC Power'  -InternalBattery-0 (id=35192931)	100%; finishing charge; 0:00 remaining present: true; lowpowermode=lowpowermode 0
host (3): host load before: 21:02  up 24 days,  9:48, 3 users, load averages: 1.60 1.59 1.69
linux (where the benchmark runs): 6.19.13-orbstack-gbd1dc07b8cf4 aarch64, cpu model not exposed, 10 vCPUs, 7.8GB (OrbStack VM, harness container)
server cpus: 0-3 (nproc 4; Postgres + app together); loadgen cpus: 4-7; harness cpus: 8-9; network: host
env (app): PORT=47130 PHX_HOST=localhost MIX_ENV=prod (image) TRUST_PROXY_HEADERS=(unset) POOL_SIZE=(default 10) UPLOADS_DIR=/data/uploads APP_EXTRA_ENV=(none) LIVEVIEW_ARGS=--deflate 1
postgres: postgres:17 port 47131 args: (defaults)
seed sha256: e233c542b4a233f4348888cdd21066d4e3549e868da99755518d5383c974967f  campfire.sql
seed sha256: 089726b88abf5f9baf1bb19b2e86beb83d3105ab976d5e6e50f6265cde324d5e  labels.json
seed sha256: 92e368f1640d4a17c6bc83bfb4f731a3426fdaa562f01f8fa0fa1fd5b45bff27  uploads/ (8 files, names+sizes)
source digest: d29e74ecdae2bbd89a0ddcc5247f0e7ac35a22ca (dirty: 12 files, diff sha256 867f1b5560b6)
workload: suites=liveview HTTP_SECS=8 HTTP_CONCS=1 16 64 CABLE_CLIENTS=100 500 1000 CABLE_TPUT_SECS=15 CABLE_POSTERS=4 DISTINCT_CLIENTS=100 500 1000 UPLOAD_REPS=5 IDLE_SECS=10 REPS=2
quiet wait: LOAD_MAX=1.5 LOAD_WAIT_SECS=900
user agent: (none)
campfire image: campfire-port:compress sha256:5f5107efc90dbd2acfec98ca644ccb7310498bd90ddb71665162cf104a2a07d5 2026-10-07T20:45:08.89661588+03:00 unpacked_bytes=261541373
postgres image id: sha256:97432f980da100ebd3e419711efee84e1e97a966d62c035286a07f239ddb4d9c 2026-09-19T00:38:59.786253347Z unpacked_bytes=476570430
loadgen image: campfire-loadgen:bench sha256:35d24d2d7e8d395ce7df23196d5c0c4984caa45e16fe64f305c7abab2f76cef2 2026-10-07T07:57:00.714539169+03:00 unpacked_bytes=101186065
```

Reps: campfire 2. Cells: median [min–max].

### Startup and memory

Memory is the sum of the app and Postgres containers for this port (per-container splits are in the raw JSON).

| Metric | campfire |
|---|---|
| cold start: docker run → /up 200 (ms) | 1,256 [1,196–1,316] |
| idle memory.current (MiB) | 518 [515–521] |
| idle anon (MiB) | 288 [280–295] |
| peak memory.current under load (MiB) | 2,758 [2,741–2,776] |
| peak anon under load (MiB) | 2,604 [2,575–2,633] |

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
| 100 clients: connect+subscribe all (s) | 0.57 [0.56–0.58] |
| 100 clients: paced post→one client p50 ms | 20.7 [20.5–20.8] |
| 100 clients: paced post→all clients p50 ms | 22.6 [22.0–23.2] |
| 100 clients: paced post→all clients p99 ms | 31.0 [29.7–32.2] |
| 100 clients: max sustained msgs/s (delivered to all) | 214 [214–215] |
| 100 clients: deliveries/s (client×message) | 21,432 [21,386–21,477] |
| 100 clients: saturated post→all p50 ms | 19.9 [19.8–19.9] |
| 100 clients: saturated POST p50 ms | 18.1 [18.0–18.2] |
| 500 clients: subscribed | 500 [500–500] |
| 500 clients: connect+subscribe all (s) | 2.58 [2.54–2.63] |
| 500 clients: paced post→one client p50 ms | 27.3 [27.2–27.3] |
| 500 clients: paced post→all clients p50 ms | 33.6 [33.5–33.6] |
| 500 clients: paced post→all clients p99 ms | 46.4 [45.8–46.9] |
| 500 clients: max sustained msgs/s (delivered to all) | 68.8 [68.7–68.9] |
| 500 clients: deliveries/s (client×message) | 34,393 [34,356–34,430] |
| 500 clients: saturated post→all p50 ms | 57.3 [57.2–57.3] |
| 500 clients: saturated POST p50 ms | 57.2 [57.1–57.3] |
| 1000 clients: subscribed | 1,000 [1,000–1,000] |
| 1000 clients: connect+subscribe all (s) | 5.44 [5.34–5.53] |
| 1000 clients: paced post→one client p50 ms | 32.6 [32.1–33.1] |
| 1000 clients: paced post→all clients p50 ms | 42.6 [41.2–44.0] |
| 1000 clients: paced post→all clients p99 ms | 75.0 [71.1–78.9] |
| 1000 clients: max sustained msgs/s (delivered to all) | 39.0 [39.0–39.0] |
| 1000 clients: deliveries/s (client×message) | 39,030 [39,027–39,032] |
| 1000 clients: saturated post→all p50 ms | 99.1 [98.8–99.4] |
| 1000 clients: saturated POST p50 ms | 101 [101–101] |

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
| 100 clients, all subscribed, idle: app process Pss | 600 [594–605] |
| 100 clients, all subscribed, idle: app process RssAnon | 526 [520–531] |
| 100 clients, all subscribed, idle: serving processes Pss | 675 [669–680] |
| 100 clients, all subscribed, idle: whole container Pss | 675 [670–681] |
| 100 clients, saturated fan-out: app process Pss | 584 [579–590] |
| 100 clients, saturated fan-out: app process RssAnon | 510 [504–516] |
| 100 clients, saturated fan-out: serving processes Pss | 665 [660–669] |
| 100 clients, saturated fan-out: whole container Pss | 664 [659–669] |
| 500 clients, all subscribed, idle: app process Pss | 1,523 [1,501–1,545] |
| 500 clients, all subscribed, idle: app process RssAnon | 1,450 [1,427–1,472] |
| 500 clients, all subscribed, idle: serving processes Pss | 1,608 [1,586–1,629] |
| 500 clients, all subscribed, idle: whole container Pss | 1,608 [1,586–1,629] |
| 500 clients, saturated fan-out: app process Pss | 1,398 [1,387–1,409] |
| 500 clients, saturated fan-out: app process RssAnon | 1,324 [1,313–1,336] |
| 500 clients, saturated fan-out: serving processes Pss | 1,483 [1,472–1,493] |
| 500 clients, saturated fan-out: whole container Pss | 1,483 [1,472–1,493] |
| 1000 clients, all subscribed, idle: app process Pss | 2,583 [2,531–2,636] |
| 1000 clients, all subscribed, idle: app process RssAnon | 2,513 [2,456–2,569] |
| 1000 clients, all subscribed, idle: serving processes Pss | 2,664 [2,616–2,711] |
| 1000 clients, all subscribed, idle: whole container Pss | 2,664 [2,616–2,711] |
| 1000 clients, saturated fan-out: app process Pss | 2,368 [2,356–2,379] |
| 1000 clients, saturated fan-out: app process RssAnon | 2,297 [2,282–2,312] |
| 1000 clients, saturated fan-out: serving processes Pss | 2,448 [2,441–2,455] |
| 1000 clients, saturated fan-out: whole container Pss | 2,448 [2,442–2,455] |

### Postgres share of CPU (this port)

`CPU µs/success` above is app + Postgres; the Postgres container's part follows.

| Metric | campfire |
|---|---|

### Background jobs at the end of each rep (Oban)

- campfire rep 1: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
- campfire rep 2: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
