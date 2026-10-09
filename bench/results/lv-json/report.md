```
date: 2026-10-07T16:42:14+0000
host: Apple M2 Pro, 10 cores (6 performance + 4 efficiency), 16GB, macOS 26.6.2
host (1): orbstack: Version: 2.1.1 (2010100); VM cpu/memory: cpu: 10 memory_mib: 8192
host (2): power: Now drawing from 'AC Power'  -InternalBattery-0 (id=35192931)	72%; charging; 0:57 remaining present: true; lowpowermode=lowpowermode 0
host (3): host load before: 19:42  up 24 days,  8:28, 3 users, load averages: 2.57 2.33 2.91
linux (where the benchmark runs): 6.19.13-orbstack-gbd1dc07b8cf4 aarch64, cpu model not exposed, 10 vCPUs, 7.8GB (OrbStack VM, harness container)
server cpus: 0-3 (nproc 4; Postgres + app together); loadgen cpus: 4-7; harness cpus: 8-9; network: host
env (app): PORT=47130 PHX_HOST=localhost MIX_ENV=prod (image) TRUST_PROXY_HEADERS=(unset) POOL_SIZE=(default 10) UPLOADS_DIR=/data/uploads APP_EXTRA_ENV=(none) LIVEVIEW_ARGS=(none)
postgres: postgres:17 port 47131 args: (defaults)
seed sha256: e233c542b4a233f4348888cdd21066d4e3549e868da99755518d5383c974967f  campfire.sql
seed sha256: 089726b88abf5f9baf1bb19b2e86beb83d3105ab976d5e6e50f6265cde324d5e  labels.json
seed sha256: 92e368f1640d4a17c6bc83bfb4f731a3426fdaa562f01f8fa0fa1fd5b45bff27  uploads/ (8 files, names+sizes)
source digest: d29e74ecdae2bbd89a0ddcc5247f0e7ac35a22ca (dirty: 1 files, diff sha256 d784bacf18f2)
workload: suites=liveview HTTP_SECS=8 HTTP_CONCS=1 16 64 CABLE_CLIENTS=100 500 1000 CABLE_TPUT_SECS=15 CABLE_POSTERS=4 DISTINCT_CLIENTS=100 500 1000 UPLOAD_REPS=5 IDLE_SECS=10 REPS=2
quiet wait: LOAD_MAX=1.5 LOAD_WAIT_SECS=900
user agent: (none)
campfire image: campfire-port:json sha256:eff099c39021be4233ade1282cf522ae4f77de3873ed47bfe59f76c185f29fa7 2026-10-07T19:42:07.149978543+03:00 unpacked_bytes=261533569
postgres image id: sha256:97432f980da100ebd3e419711efee84e1e97a966d62c035286a07f239ddb4d9c 2026-09-19T00:38:59.786253347Z unpacked_bytes=476570430
loadgen image: campfire-loadgen:bench sha256:35d24d2d7e8d395ce7df23196d5c0c4984caa45e16fe64f305c7abab2f76cef2 2026-10-07T07:57:00.714539169+03:00 unpacked_bytes=101186065
```

Reps: campfire 2. Cells: median [min–max].

### Startup and memory

Memory is the sum of the app and Postgres containers for this port (per-container splits are in the raw JSON).

| Metric | campfire |
|---|---|
| cold start: docker run → /up 200 (ms) | 1,168 [1,150–1,186] |
| idle memory.current (MiB) | 536 [520–551] |
| idle anon (MiB) | 282 [281–284] |
| peak memory.current under load (MiB) | 2,478 [2,472–2,484] |
| peak anon under load (MiB) | 2,308 [2,280–2,335] |

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
| 100 clients: connect+subscribe all (s) | 0.65 [0.63–0.67] |
| 100 clients: paced post→one client p50 ms | 22.8 [22.6–23.0] |
| 100 clients: paced post→all clients p50 ms | 24.0 [23.8–24.1] |
| 100 clients: paced post→all clients p99 ms | 31.4 [31.0–31.8] |
| 100 clients: max sustained msgs/s (delivered to all) | 127 [126–128] |
| 100 clients: deliveries/s (client×message) | 12,736 [12,646–12,825] |
| 100 clients: saturated post→all p50 ms | 31.2 [31.0–31.3] |
| 100 clients: saturated POST p50 ms | 30.9 [30.7–31.0] |
| 500 clients: subscribed | 500 [500–500] |
| 500 clients: connect+subscribe all (s) | 2.77 [2.62–2.92] |
| 500 clients: paced post→one client p50 ms | 38.4 [38.4–38.4] |
| 500 clients: paced post→all clients p50 ms | 44.6 [43.8–45.3] |
| 500 clients: paced post→all clients p99 ms | 63.0 [58.2–67.8] |
| 500 clients: max sustained msgs/s (delivered to all) | 38.0 [37.2–38.8] |
| 500 clients: deliveries/s (client×message) | 18,998 [18,607–19,390] |
| 500 clients: saturated post→all p50 ms | 105 [103–108] |
| 500 clients: saturated POST p50 ms | 104 [101–106] |
| 1000 clients: subscribed | 1,000 [1,000–1,000] |
| 1000 clients: connect+subscribe all (s) | 5.76 [5.71–5.81] |
| 1000 clients: paced post→one client p50 ms | 52.3 [51.0–53.5] |
| 1000 clients: paced post→all clients p50 ms | 61.7 [60.9–62.6] |
| 1000 clients: paced post→all clients p99 ms | 129 [122–135] |
| 1000 clients: max sustained msgs/s (delivered to all) | 20.7 [19.9–21.5] |
| 1000 clients: deliveries/s (client×message) | 20,676 [19,867–21,485] |
| 1000 clients: saturated post→all p50 ms | 194 [183–205] |
| 1000 clients: saturated POST p50 ms | 190 [180–200] |

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
| 100 clients, all subscribed, idle: app process Pss | 578 [576–581] |
| 100 clients, all subscribed, idle: app process RssAnon | 505 [503–506] |
| 100 clients, all subscribed, idle: serving processes Pss | 653 [651–656] |
| 100 clients, all subscribed, idle: whole container Pss | 654 [651–656] |
| 100 clients, saturated fan-out: app process Pss | 545 [529–561] |
| 100 clients, saturated fan-out: app process RssAnon | 471 [454–488] |
| 100 clients, saturated fan-out: serving processes Pss | 625 [608–641] |
| 100 clients, saturated fan-out: whole container Pss | 624 [609–640] |
| 500 clients, all subscribed, idle: app process Pss | 1,378 [1,367–1,389] |
| 500 clients, all subscribed, idle: app process RssAnon | 1,304 [1,293–1,316] |
| 500 clients, all subscribed, idle: serving processes Pss | 1,462 [1,450–1,473] |
| 500 clients, all subscribed, idle: whole container Pss | 1,462 [1,450–1,473] |
| 500 clients, saturated fan-out: app process Pss | 1,225 [1,130–1,320] |
| 500 clients, saturated fan-out: app process RssAnon | 1,151 [1,055–1,247] |
| 500 clients, saturated fan-out: serving processes Pss | 1,309 [1,213–1,405] |
| 500 clients, saturated fan-out: whole container Pss | 1,309 [1,212–1,405] |
| 1000 clients, all subscribed, idle: app process Pss | 2,332 [2,309–2,354] |
| 1000 clients, all subscribed, idle: app process RssAnon | 2,262 [2,235–2,288] |
| 1000 clients, all subscribed, idle: serving processes Pss | 2,414 [2,392–2,435] |
| 1000 clients, all subscribed, idle: whole container Pss | 2,414 [2,393–2,435] |
| 1000 clients, saturated fan-out: app process Pss | 2,082 [1,859–2,306] |
| 1000 clients, saturated fan-out: app process RssAnon | 2,015 [1,791–2,239] |
| 1000 clients, saturated fan-out: serving processes Pss | 2,165 [1,942–2,388] |
| 1000 clients, saturated fan-out: whole container Pss | 2,164 [1,942–2,386] |

### Postgres share of CPU (this port)

`CPU µs/success` above is app + Postgres; the Postgres container's part follows.

| Metric | campfire |
|---|---|

### Background jobs at the end of each rep (Oban)

- campfire rep 1: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
- campfire rep 2: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
