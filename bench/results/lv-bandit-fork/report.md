```
date: 2026-10-07T18:13:58+0000
host: Apple M2 Pro, 10 cores (6 performance + 4 efficiency), 16GB, macOS 26.6.2
host (1): orbstack: Version: 2.1.1 (2010100); VM cpu/memory: cpu: 10 memory_mib: 8192
host (2): power: Now drawing from 'AC Power'  -InternalBattery-0 (id=35192931)	100%; charged; 0:00 remaining present: true; lowpowermode=lowpowermode 0
host (3): host load before: 21:13  up 24 days, 10 hrs, 3 users, load averages: 2.01 1.54 1.60
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
campfire image: campfire-port:bandit-fork sha256:3dc0a3bae8e6fdaae9c102c586b022edbf0f3b43af0c1f32323ce00d558928ef 2026-10-07T21:13:28.361443882+03:00 unpacked_bytes=261542733
postgres image id: sha256:97432f980da100ebd3e419711efee84e1e97a966d62c035286a07f239ddb4d9c 2026-09-19T00:38:59.786253347Z unpacked_bytes=476570430
loadgen image: campfire-loadgen:bench sha256:35d24d2d7e8d395ce7df23196d5c0c4984caa45e16fe64f305c7abab2f76cef2 2026-10-07T07:57:00.714539169+03:00 unpacked_bytes=101186065
```

Reps: campfire 2. Cells: median [min–max].

### Startup and memory

Memory is the sum of the app and Postgres containers for this port (per-container splits are in the raw JSON).

| Metric | campfire |
|---|---|
| cold start: docker run → /up 200 (ms) | 1,238 [1,208–1,267] |
| idle memory.current (MiB) | 562 [552–571] |
| idle anon (MiB) | 296 [287–305] |
| peak memory.current under load (MiB) | 2,306 [2,255–2,357] |
| peak anon under load (MiB) | 2,145 [2,065–2,225] |

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
| 100 clients: connect+subscribe all (s) | 0.53 [0.52–0.54] |
| 100 clients: paced post→one client p50 ms | 18.2 [18.0–18.4] |
| 100 clients: paced post→all clients p50 ms | 19.0 [18.9–19.2] |
| 100 clients: paced post→all clients p99 ms | 24.4 [24.0–24.9] |
| 100 clients: max sustained msgs/s (delivered to all) | 286 [284–287] |
| 100 clients: deliveries/s (client×message) | 28,576 [28,433–28,720] |
| 100 clients: saturated post→all p50 ms | 15.0 [14.9–15.0] |
| 100 clients: saturated POST p50 ms | 13.5 [13.4–13.6] |
| 500 clients: subscribed | 500 [500–500] |
| 500 clients: connect+subscribe all (s) | 2.49 [2.45–2.53] |
| 500 clients: paced post→one client p50 ms | 23.8 [22.8–24.8] |
| 500 clients: paced post→all clients p50 ms | 26.0 [25.1–26.9] |
| 500 clients: paced post→all clients p99 ms | 33.7 [32.6–34.8] |
| 500 clients: max sustained msgs/s (delivered to all) | 134 [133–135] |
| 500 clients: deliveries/s (client×message) | 66,910 [66,480–67,341] |
| 500 clients: saturated post→all p50 ms | 29.9 [29.5–30.3] |
| 500 clients: saturated POST p50 ms | 29.4 [29.1–29.6] |
| 1000 clients: subscribed | 1,000 [1,000–1,000] |
| 1000 clients: connect+subscribe all (s) | 5.03 [5.02–5.03] |
| 1000 clients: paced post→one client p50 ms | 28.8 [28.0–29.6] |
| 1000 clients: paced post→all clients p50 ms | 33.6 [32.0–35.2] |
| 1000 clients: paced post→all clients p99 ms | 49.4 [47.7–51.2] |
| 1000 clients: max sustained msgs/s (delivered to all) | 79.2 [78.5–80.0] |
| 1000 clients: deliveries/s (client×message) | 79,266 [78,517–80,014] |
| 1000 clients: saturated post→all p50 ms | 49.3 [48.6–50.0] |
| 1000 clients: saturated POST p50 ms | 49.6 [49.3–50.0] |

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
| 100 clients, all subscribed, idle: app process Pss | 545 [538–552] |
| 100 clients, all subscribed, idle: app process RssAnon | 471 [464–477] |
| 100 clients, all subscribed, idle: serving processes Pss | 620 [614–627] |
| 100 clients, all subscribed, idle: whole container Pss | 621 [614–627] |
| 100 clients, saturated fan-out: app process Pss | 553 [544–562] |
| 100 clients, saturated fan-out: app process RssAnon | 479 [470–488] |
| 100 clients, saturated fan-out: serving processes Pss | 634 [625–643] |
| 100 clients, saturated fan-out: whole container Pss | 632 [623–641] |
| 500 clients, all subscribed, idle: app process Pss | 1,235 [1,180–1,289] |
| 500 clients, all subscribed, idle: app process RssAnon | 1,160 [1,106–1,215] |
| 500 clients, all subscribed, idle: serving processes Pss | 1,321 [1,266–1,376] |
| 500 clients, all subscribed, idle: whole container Pss | 1,321 [1,267–1,376] |
| 500 clients, saturated fan-out: app process Pss | 1,308 [1,278–1,338] |
| 500 clients, saturated fan-out: app process RssAnon | 1,234 [1,204–1,264] |
| 500 clients, saturated fan-out: serving processes Pss | 1,396 [1,365–1,428] |
| 500 clients, saturated fan-out: whole container Pss | 1,395 [1,365–1,424] |
| 1000 clients, all subscribed, idle: app process Pss | 2,049 [1,946–2,151] |
| 1000 clients, all subscribed, idle: app process RssAnon | 1,979 [1,872–2,086] |
| 1000 clients, all subscribed, idle: serving processes Pss | 2,136 [2,034–2,238] |
| 1000 clients, all subscribed, idle: whole container Pss | 2,136 [2,034–2,238] |
| 1000 clients, saturated fan-out: app process Pss | 2,162 [2,084–2,240] |
| 1000 clients, saturated fan-out: app process RssAnon | 2,092 [2,010–2,174] |
| 1000 clients, saturated fan-out: serving processes Pss | 2,252 [2,171–2,332] |
| 1000 clients, saturated fan-out: whole container Pss | 2,249 [2,172–2,327] |

### Postgres share of CPU (this port)

`CPU µs/success` above is app + Postgres; the Postgres container's part follows.

| Metric | campfire |
|---|---|

### Background jobs at the end of each rep (Oban)

- campfire rep 1: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
- campfire rep 2: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
