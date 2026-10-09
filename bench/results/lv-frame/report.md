```
date: 2026-10-07T16:51:58+0000
host: Apple M2 Pro, 10 cores (6 performance + 4 efficiency), 16GB, macOS 26.6.2
host (1): orbstack: Version: 2.1.1 (2010100); VM cpu/memory: cpu: 10 memory_mib: 8192
host (2): power: Now drawing from 'AC Power'  -InternalBattery-0 (id=35192931)	82%; charging; 0:41 remaining present: true; lowpowermode=lowpowermode 0
host (3): host load before: 19:51  up 24 days,  8:38, 3 users, load averages: 1.97 1.97 2.45
linux (where the benchmark runs): 6.19.13-orbstack-gbd1dc07b8cf4 aarch64, cpu model not exposed, 10 vCPUs, 7.8GB (OrbStack VM, harness container)
server cpus: 0-3 (nproc 4; Postgres + app together); loadgen cpus: 4-7; harness cpus: 8-9; network: host
env (app): PORT=47130 PHX_HOST=localhost MIX_ENV=prod (image) TRUST_PROXY_HEADERS=(unset) POOL_SIZE=(default 10) UPLOADS_DIR=/data/uploads APP_EXTRA_ENV=(none) LIVEVIEW_ARGS=(none)
postgres: postgres:17 port 47131 args: (defaults)
seed sha256: e233c542b4a233f4348888cdd21066d4e3549e868da99755518d5383c974967f  campfire.sql
seed sha256: 089726b88abf5f9baf1bb19b2e86beb83d3105ab976d5e6e50f6265cde324d5e  labels.json
seed sha256: 92e368f1640d4a17c6bc83bfb4f731a3426fdaa562f01f8fa0fa1fd5b45bff27  uploads/ (8 files, names+sizes)
source digest: d29e74ecdae2bbd89a0ddcc5247f0e7ac35a22ca (dirty: 5 files, diff sha256 ba8dfb74cf63)
workload: suites=liveview HTTP_SECS=8 HTTP_CONCS=1 16 64 CABLE_CLIENTS=100 500 1000 CABLE_TPUT_SECS=15 CABLE_POSTERS=4 DISTINCT_CLIENTS=100 500 1000 UPLOAD_REPS=5 IDLE_SECS=10 REPS=2
quiet wait: LOAD_MAX=1.5 LOAD_WAIT_SECS=900
user agent: (none)
campfire image: campfire-port:frame sha256:4243f39b5ca54046b08085a20ac7f7a3a4a764fb3509db267a18e714b1c2aaed 2026-10-07T19:51:33.265328012+03:00 unpacked_bytes=261536297
postgres image id: sha256:97432f980da100ebd3e419711efee84e1e97a966d62c035286a07f239ddb4d9c 2026-09-19T00:38:59.786253347Z unpacked_bytes=476570430
loadgen image: campfire-loadgen:bench sha256:35d24d2d7e8d395ce7df23196d5c0c4984caa45e16fe64f305c7abab2f76cef2 2026-10-07T07:57:00.714539169+03:00 unpacked_bytes=101186065
```

Reps: campfire 2. Cells: median [min–max].

### Startup and memory

Memory is the sum of the app and Postgres containers for this port (per-container splits are in the raw JSON).

| Metric | campfire |
|---|---|
| cold start: docker run → /up 200 (ms) | 1,226 [1,222–1,229] |
| idle memory.current (MiB) | 492 [462–522] |
| idle anon (MiB) | 296 [289–303] |
| peak memory.current under load (MiB) | 2,676 [2,656–2,697] |
| peak anon under load (MiB) | 2,516 [2,510–2,523] |

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
| 100 clients: connect+subscribe all (s) | 0.58 [0.57–0.59] |
| 100 clients: paced post→one client p50 ms | 20.5 [19.4–21.5] |
| 100 clients: paced post→all clients p50 ms | 21.4 [20.3–22.5] |
| 100 clients: paced post→all clients p99 ms | 29.8 [27.6–32.1] |
| 100 clients: max sustained msgs/s (delivered to all) | 152 [149–155] |
| 100 clients: deliveries/s (client×message) | 15,192 [14,903–15,482] |
| 100 clients: saturated post→all p50 ms | 25.7 [25.2–26.2] |
| 100 clients: saturated POST p50 ms | 25.6 [25.1–26.1] |
| 500 clients: subscribed | 500 [500–500] |
| 500 clients: connect+subscribe all (s) | 2.79 [2.74–2.83] |
| 500 clients: paced post→one client p50 ms | 28.5 [28.3–28.7] |
| 500 clients: paced post→all clients p50 ms | 32.6 [32.2–32.9] |
| 500 clients: paced post→all clients p99 ms | 54.4 [44.4–64.4] |
| 500 clients: max sustained msgs/s (delivered to all) | 57.0 [56.3–57.8] |
| 500 clients: deliveries/s (client×message) | 28,514 [28,150–28,878] |
| 500 clients: saturated post→all p50 ms | 68.7 [67.8–69.6] |
| 500 clients: saturated POST p50 ms | 68.6 [68.0–69.2] |
| 1000 clients: subscribed | 1,000 [1,000–1,000] |
| 1000 clients: connect+subscribe all (s) | 5.73 [5.58–5.88] |
| 1000 clients: paced post→one client p50 ms | 40.2 [38.7–41.7] |
| 1000 clients: paced post→all clients p50 ms | 46.7 [45.9–47.6] |
| 1000 clients: paced post→all clients p99 ms | 82.9 [77.6–88.2] |
| 1000 clients: max sustained msgs/s (delivered to all) | 34.1 [34.0–34.2] |
| 1000 clients: deliveries/s (client×message) | 34,142 [34,048–34,236] |
| 1000 clients: saturated post→all p50 ms | 115 [114–115] |
| 1000 clients: saturated POST p50 ms | 115 [115–116] |

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
| 100 clients, all subscribed, idle: app process Pss | 588 [586–590] |
| 100 clients, all subscribed, idle: app process RssAnon | 517 [516–518] |
| 100 clients, all subscribed, idle: serving processes Pss | 663 [661–665] |
| 100 clients, all subscribed, idle: whole container Pss | 664 [662–666] |
| 100 clients, saturated fan-out: app process Pss | 542 [537–547] |
| 100 clients, saturated fan-out: app process RssAnon | 471 [462–479] |
| 100 clients, saturated fan-out: serving processes Pss | 625 [618–632] |
| 100 clients, saturated fan-out: whole container Pss | 622 [617–627] |
| 500 clients, all subscribed, idle: app process Pss | 1,412 [1,400–1,425] |
| 500 clients, all subscribed, idle: app process RssAnon | 1,342 [1,332–1,351] |
| 500 clients, all subscribed, idle: serving processes Pss | 1,498 [1,485–1,510] |
| 500 clients, all subscribed, idle: whole container Pss | 1,498 [1,486–1,510] |
| 500 clients, saturated fan-out: app process Pss | 1,137 [1,121–1,153] |
| 500 clients, saturated fan-out: app process RssAnon | 1,068 [1,057–1,079] |
| 500 clients, saturated fan-out: serving processes Pss | 1,223 [1,209–1,238] |
| 500 clients, saturated fan-out: whole container Pss | 1,222 [1,207–1,238] |
| 1000 clients, all subscribed, idle: app process Pss | 2,375 [2,367–2,384] |
| 1000 clients, all subscribed, idle: app process RssAnon | 2,306 [2,303–2,310] |
| 1000 clients, all subscribed, idle: serving processes Pss | 2,461 [2,453–2,469] |
| 1000 clients, all subscribed, idle: whole container Pss | 2,461 [2,453–2,469] |
| 1000 clients, saturated fan-out: app process Pss | 1,795 [1,792–1,798] |
| 1000 clients, saturated fan-out: app process RssAnon | 1,726 [1,724–1,728] |
| 1000 clients, saturated fan-out: serving processes Pss | 1,882 [1,880–1,883] |
| 1000 clients, saturated fan-out: whole container Pss | 1,881 [1,878–1,884] |

### Postgres share of CPU (this port)

`CPU µs/success` above is app + Postgres; the Postgres container's part follows.

| Metric | campfire |
|---|---|

### Background jobs at the end of each rep (Oban)

- campfire rep 1: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
- campfire rep 2: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
