```
date: 2026-10-07T16:31:51+0000
host: Apple M2 Pro, 10 cores (6 performance + 4 efficiency), 16GB, macOS 26.6.2
host (1): orbstack: Version: 2.1.1 (2010100); VM cpu/memory: cpu: 10 memory_mib: 8192
host (2): power: Now drawing from 'AC Power'  -InternalBattery-0 (id=35192931)	58%; charging; 1:10 remaining present: true; lowpowermode=lowpowermode 0
host (3): host load before: 19:31  up 24 days,  8:18, 3 users, load averages: 3.64 4.19 3.76
linux (where the benchmark runs): 6.19.13-orbstack-gbd1dc07b8cf4 aarch64, cpu model not exposed, 10 vCPUs, 7.8GB (OrbStack VM, harness container)
server cpus: 0-3 (nproc 4; Postgres + app together); loadgen cpus: 4-7; harness cpus: 8-9; network: host
env (app): PORT=47130 PHX_HOST=localhost MIX_ENV=prod (image) TRUST_PROXY_HEADERS=(unset) POOL_SIZE=(default 10) UPLOADS_DIR=/data/uploads APP_EXTRA_ENV=(none) LIVEVIEW_ARGS=(none)
postgres: postgres:17 port 47131 args: (defaults)
seed sha256: e233c542b4a233f4348888cdd21066d4e3549e868da99755518d5383c974967f  campfire.sql
seed sha256: 089726b88abf5f9baf1bb19b2e86beb83d3105ab976d5e6e50f6265cde324d5e  labels.json
seed sha256: 92e368f1640d4a17c6bc83bfb4f731a3426fdaa562f01f8fa0fa1fd5b45bff27  uploads/ (8 files, names+sizes)
source digest: d29e74ecdae2bbd89a0ddcc5247f0e7ac35a22ca (dirty: 0 files)
workload: suites=liveview HTTP_SECS=8 HTTP_CONCS=1 16 64 CABLE_CLIENTS=100 500 1000 CABLE_TPUT_SECS=15 CABLE_POSTERS=4 DISTINCT_CLIENTS=100 500 1000 UPLOAD_REPS=5 IDLE_SECS=10 REPS=2
quiet wait: LOAD_MAX=1.5 LOAD_WAIT_SECS=900
user agent: (none)
campfire image: campfire-port:baseline sha256:5e7a976e1ede695ca1f2b8068222ea5bb670c6bdbb3e5b67bf98f730201bcad2 2026-10-07T07:40:32.656275354+03:00 unpacked_bytes=261533574
postgres image id: sha256:97432f980da100ebd3e419711efee84e1e97a966d62c035286a07f239ddb4d9c 2026-09-19T00:38:59.786253347Z unpacked_bytes=476570430
loadgen image: campfire-loadgen:bench sha256:35d24d2d7e8d395ce7df23196d5c0c4984caa45e16fe64f305c7abab2f76cef2 2026-10-07T07:57:00.714539169+03:00 unpacked_bytes=101186065
```

Reps: campfire 2. Cells: median [min–max].

### Startup and memory

Memory is the sum of the app and Postgres containers for this port (per-container splits are in the raw JSON).

| Metric | campfire |
|---|---|
| cold start: docker run → /up 200 (ms) | 1,202 [1,146–1,257] |
| idle memory.current (MiB) | 520 [504–535] |
| idle anon (MiB) | 284 [278–291] |
| peak memory.current under load (MiB) | 3,384 [3,345–3,424] |
| peak anon under load (MiB) | 3,238 [3,224–3,251] |

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
| 100 clients: connect+subscribe all (s) | 0.64 [0.63–0.64] |
| 100 clients: paced post→one client p50 ms | 21.2 [20.6–21.7] |
| 100 clients: paced post→all clients p50 ms | 23.3 [22.7–23.9] |
| 100 clients: paced post→all clients p99 ms | 37.0 [33.9–40.1] |
| 100 clients: max sustained msgs/s (delivered to all) | 122 [122–123] |
| 100 clients: deliveries/s (client×message) | 12,234 [12,164–12,305] |
| 100 clients: saturated post→all p50 ms | 32.3 [32.1–32.5] |
| 100 clients: saturated POST p50 ms | 32.0 [31.8–32.3] |
| 500 clients: subscribed | 500 [500–500] |
| 500 clients: connect+subscribe all (s) | 2.80 [2.78–2.82] |
| 500 clients: paced post→one client p50 ms | 36.5 [35.6–37.4] |
| 500 clients: paced post→all clients p50 ms | 43.0 [41.2–44.8] |
| 500 clients: paced post→all clients p99 ms | 93.5 [88.1–98.9] |
| 500 clients: max sustained msgs/s (delivered to all) | 36.8 [36.5–37.1] |
| 500 clients: deliveries/s (client×message) | 18,410 [18,256–18,565] |
| 500 clients: saturated post→all p50 ms | 108 [107–109] |
| 500 clients: saturated POST p50 ms | 106 [106–107] |
| 1000 clients: subscribed | 1,000 [1,000–1,000] |
| 1000 clients: connect+subscribe all (s) | 5.72 [5.69–5.76] |
| 1000 clients: paced post→one client p50 ms | 60.0 [59.3–60.6] |
| 1000 clients: paced post→all clients p50 ms | 73.1 [72.5–73.7] |
| 1000 clients: paced post→all clients p99 ms | 196 [191–202] |
| 1000 clients: max sustained msgs/s (delivered to all) | 19.6 [19.3–19.9] |
| 1000 clients: deliveries/s (client×message) | 19,632 [19,335–19,930] |
| 1000 clients: saturated post→all p50 ms | 204 [201–208] |
| 1000 clients: saturated POST p50 ms | 200 [197–202] |

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
| 100 clients, all subscribed, idle: app process Pss | 570 [559–582] |
| 100 clients, all subscribed, idle: app process RssAnon | 496 [484–508] |
| 100 clients, all subscribed, idle: serving processes Pss | 646 [634–658] |
| 100 clients, all subscribed, idle: whole container Pss | 646 [634–658] |
| 100 clients, saturated fan-out: app process Pss | 521 [498–543] |
| 100 clients, saturated fan-out: app process RssAnon | 446 [424–468] |
| 100 clients, saturated fan-out: serving processes Pss | 600 [577–622] |
| 100 clients, saturated fan-out: whole container Pss | 599 [577–622] |
| 500 clients, all subscribed, idle: app process Pss | 1,278 [1,265–1,291] |
| 500 clients, all subscribed, idle: app process RssAnon | 1,205 [1,192–1,218] |
| 500 clients, all subscribed, idle: serving processes Pss | 1,362 [1,349–1,376] |
| 500 clients, all subscribed, idle: whole container Pss | 1,363 [1,349–1,376] |
| 500 clients, saturated fan-out: app process Pss | 1,083 [981–1,185] |
| 500 clients, saturated fan-out: app process RssAnon | 1,010 [908–1,112] |
| 500 clients, saturated fan-out: serving processes Pss | 1,168 [1,066–1,270] |
| 500 clients, saturated fan-out: whole container Pss | 1,168 [1,065–1,270] |
| 1000 clients, all subscribed, idle: app process Pss | 2,128 [2,108–2,148] |
| 1000 clients, all subscribed, idle: app process RssAnon | 2,058 [2,042–2,074] |
| 1000 clients, all subscribed, idle: serving processes Pss | 2,208 [2,184–2,233] |
| 1000 clients, all subscribed, idle: whole container Pss | 2,208 [2,184–2,233] |
| 1000 clients, saturated fan-out: app process Pss | 1,737 [1,534–1,941] |
| 1000 clients, saturated fan-out: app process RssAnon | 1,671 [1,467–1,874] |
| 1000 clients, saturated fan-out: serving processes Pss | 1,819 [1,613–2,026] |
| 1000 clients, saturated fan-out: whole container Pss | 1,813 [1,610–2,016] |

### Postgres share of CPU (this port)

`CPU µs/success` above is app + Postgres; the Postgres container's part follows.

| Metric | campfire |
|---|---|

### Background jobs at the end of each rep (Oban)

- campfire rep 1: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
- campfire rep 2: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
