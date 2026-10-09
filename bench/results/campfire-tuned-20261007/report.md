```
date: 2026-10-07T18:23:06+0000
host: Apple M2 Pro, 10 cores (6 performance + 4 efficiency), 16GB, macOS 26.6.2
host (1): orbstack: Version: 2.1.1 (2010100); VM cpu/memory: cpu: 10 memory_mib: 8192
host (2): power: Now drawing from 'AC Power'  -InternalBattery-0 (id=35192931)	100%; charged; 0:00 remaining present: true; lowpowermode=lowpowermode 0
host (3): host load before: 21:23  up 24 days, 10:09, 3 users, load averages: 1.56 1.61 1.65
linux (where the benchmark runs): 6.19.13-orbstack-gbd1dc07b8cf4 aarch64, cpu model not exposed, 10 vCPUs, 7.8GB (OrbStack VM, harness container)
server cpus: 0-3 (nproc 4; Postgres + app together); loadgen cpus: 4-7; harness cpus: 8-9; network: host
env (app): PORT=47130 PHX_HOST=localhost MIX_ENV=prod (image) TRUST_PROXY_HEADERS=(unset) POOL_SIZE=(default 10) UPLOADS_DIR=/data/uploads APP_EXTRA_ENV=(none) LIVEVIEW_ARGS=(none)
postgres: postgres:17 port 47131 args: (defaults)
seed sha256: e233c542b4a233f4348888cdd21066d4e3549e868da99755518d5383c974967f  campfire.sql
seed sha256: 089726b88abf5f9baf1bb19b2e86beb83d3105ab976d5e6e50f6265cde324d5e  labels.json
seed sha256: 92e368f1640d4a17c6bc83bfb4f731a3426fdaa562f01f8fa0fa1fd5b45bff27  uploads/ (8 files, names+sizes)
source digest: d29e74ecdae2bbd89a0ddcc5247f0e7ac35a22ca (dirty: 12 files, diff sha256 5a67e3f272dc)
workload: suites=http liveview HTTP_SECS=4 HTTP_CONCS=1 16 64 CABLE_CLIENTS=100 500 1000 CABLE_TPUT_SECS=15 CABLE_POSTERS=4 DISTINCT_CLIENTS=100 500 1000 UPLOAD_REPS=5 IDLE_SECS=10 REPS=2
quiet wait: LOAD_MAX=1.5 LOAD_WAIT_SECS=900
user agent: (none)
campfire image: campfire-port:bench sha256:d09f6b7e4bc9aaf3cd721719a32e17c2e976d7fe3873d9fd2cf868c3899ef3f2 2026-10-07T21:22:44.583150649+03:00 unpacked_bytes=261541357
postgres image id: sha256:97432f980da100ebd3e419711efee84e1e97a966d62c035286a07f239ddb4d9c 2026-09-19T00:38:59.786253347Z unpacked_bytes=476570430
loadgen image: campfire-loadgen:bench sha256:35d24d2d7e8d395ce7df23196d5c0c4984caa45e16fe64f305c7abab2f76cef2 2026-10-07T07:57:00.714539169+03:00 unpacked_bytes=101186065
```

Reps: campfire 2. Cells: median [min–max].

### Startup and memory

Memory is the sum of the app and Postgres containers for this port (per-container splits are in the raw JSON).

| Metric | campfire |
|---|---|
| cold start: docker run → /up 200 (ms) | 1,225 [1,134–1,316] |
| idle memory.current (MiB) | 550 [530–569] |
| idle anon (MiB) | 292 [280–304] |
| peak memory.current under load (MiB) | 2,300 [2,237–2,362] |
| peak anon under load (MiB) | 2,164 [2,107–2,222] |

### HTTP (signed in; keep-alive; c = concurrent connections)

Signed in as David for session routes; `messages_page` and `post_message` use the bot API (no session).

| Metric | campfire |
|---|---|
| room_show c=1 req/s | 120 [119–120] |
| room_show c=1 p50 ms | 8.20 [8.18–8.22] |
| room_show c=1 p99 ms | 11.7 [11.5–12.0] |
| room_show c=1 CPU µs/success | 9,759 [9,658–9,860] |
| room_show c=16 req/s | 456 [454–458] |
| room_show c=16 p50 ms | 33.3 [33.3–33.3] |
| room_show c=16 p99 ms | 87.1 [86.8–87.5] |
| room_show c=16 CPU µs/success | 8,450 [8,384–8,515] |
| room_show c=64 req/s | 460 [457–462] |
| room_show c=64 p50 ms | 139 [138–140] |
| room_show c=64 p99 ms | 189 [188–190] |
| room_show c=64 CPU µs/success | 8,201 [8,116–8,285] |
| messages_page c=1 req/s | 120 [118–122] |
| messages_page c=1 p50 ms | 7.77 [7.75–7.78] |
| messages_page c=1 p99 ms | 14.5 [14.4–14.6] |
| messages_page c=1 CPU µs/success | 10,851 [10,797–10,906] |
| messages_page c=16 req/s | 519 [513–524] |
| messages_page c=16 p50 ms | 29.2 [29.1–29.3] |
| messages_page c=16 p99 ms | 76.0 [73.9–78.1] |
| messages_page c=16 CPU µs/success | 7,457 [7,378–7,536] |
| messages_page c=64 req/s | 523 [521–526] |
| messages_page c=64 p50 ms | 121 [121–121] |
| messages_page c=64 p99 ms | 187 [183–190] |
| messages_page c=64 CPU µs/success | 7,349 [7,291–7,407] |
| search c=1 req/s | 321 [316–326] |
| search c=1 p50 ms | 2.96 [2.94–2.99] |
| search c=1 p99 ms | 6.42 [6.26–6.58] |
| search c=1 CPU µs/success | 4,061 [4,015–4,108] |
| search c=16 req/s | 1,394 [1,391–1,397] |
| search c=16 p50 ms | 11.0 [11.0–11.0] |
| search c=16 p99 ms | 34.0 [23.6–44.4] |
| search c=16 CPU µs/success | 2,774 [2,773–2,775] |
| search c=64 req/s | 1,398 [1,398–1,398] |
| search c=64 p50 ms | 45.4 [45.2–45.5] |
| search c=64 p99 ms | 63.5 [62.6–64.5] |
| search c=64 CPU µs/success | 2,743 [2,741–2,745] |
| avatar c=1 req/s | 1,136 [1,125–1,147] |
| avatar c=1 p50 ms | 0.83 [0.83–0.83] |
| avatar c=1 p99 ms | 1.29 [1.24–1.34] |
| avatar c=1 CPU µs/success | 1,114 [1,112–1,115] |
| avatar c=16 req/s | 4,193 [4,189–4,196] |
| avatar c=16 p50 ms | 3.62 [3.61–3.63] |
| avatar c=16 p99 ms | 7.85 [7.82–7.88] |
| avatar c=16 CPU µs/success | 887 [886–888] |
| avatar c=64 req/s | 4,421 [4,408–4,434] |
| avatar c=64 p50 ms | 14.2 [14.2–14.3] |
| avatar c=64 p99 ms | 21.5 [20.9–22.0] |
| avatar c=64 CPU µs/success | 862 [860–864] |
| static_css c=1 req/s | 8,162 [7,891–8,433] |
| static_css c=1 p50 ms | 0.11 [0.11–0.12] |
| static_css c=1 p99 ms | 0.24 [0.23–0.25] |
| static_css c=1 CPU µs/success | 226 [220–233] |
| static_css c=16 req/s | 27,650 [27,587–27,713] |
| static_css c=16 p50 ms | 0.46 [0.45–0.46] |
| static_css c=16 p99 ms | 2.12 [2.09–2.15] |
| static_css c=16 CPU µs/success | 134 [134–134] |
| static_css c=64 req/s | 31,624 [31,068–32,180] |
| static_css c=64 p50 ms | 1.85 [1.80–1.89] |
| static_css c=64 p99 ms | 5.21 [5.16–5.25] |
| static_css c=64 CPU µs/success | 118 [116–120] |
| up c=1 req/s | 12,282 [12,247–12,318] |
| up c=1 p50 ms | 0.08 [0.08–0.08] |
| up c=1 p99 ms | 0.12 [0.12–0.13] |
| up c=1 CPU µs/success | 87.3 [86.2–88.4] |
| up c=16 req/s | 43,348 [42,425–44,270] |
| up c=16 p50 ms | 0.27 [0.26–0.27] |
| up c=16 p99 ms | 1.64 [1.61–1.67] |
| up c=16 CPU µs/success | 55.7 [55.7–55.7] |
| up c=64 req/s | 44,007 [41,586–46,428] |
| up c=64 p50 ms | 1.27 [1.21–1.33] |
| up c=64 p99 ms | 5.11 [4.87–5.34] |
| up c=64 CPU µs/success | 58.4 [57.1–59.7] |
| post_message c=1 req/s | 220 [214–226] |
| post_message c=1 p50 ms | 4.47 [4.37–4.58] |
| post_message c=1 p99 ms | 6.67 [6.25–7.10] |
| post_message c=1 CPU µs/success | 4,199 [3,985–4,413] |
| post_message c=16 req/s | 362 [362–362] |
| post_message c=16 p50 ms | 38.0 [38.0–38.1] |
| post_message c=16 p99 ms | 125 [124–127] |
| post_message c=16 CPU µs/success | 4,146 [4,094–4,199] |
| post_message c=64 req/s | 376 [374–377] |
| post_message c=64 p50 ms | 160 [158–162] |
| post_message c=64 p99 ms | 265 [249–280] |
| post_message c=64 CPU µs/success | 3,985 [3,958–4,013] |

### HTTP errors / non-2xx-3xx (first rep, per app)

- campfire: none
- skipped workload `sidebar`: no HTTP endpoint in this app: LiveView renders the sidebar inside the page/socket

### LiveView fan-out, one room, one signed-in user (upstream columns: Action Cable, chatter.js subscriptions per client)

| Metric | campfire |
|---|---|
| 100 clients: subscribed | 100 [100–100] |
| 100 clients: connect+subscribe all (s) | 0.59 [0.57–0.61] |
| 100 clients: paced post→one client p50 ms | 17.6 [17.6–17.7] |
| 100 clients: paced post→all clients p50 ms | 18.7 [18.6–18.8] |
| 100 clients: paced post→all clients p99 ms | 25.3 [25.0–25.5] |
| 100 clients: max sustained msgs/s (delivered to all) | 277 [275–278] |
| 100 clients: deliveries/s (client×message) | 27,673 [27,503–27,843] |
| 100 clients: saturated post→all p50 ms | 15.5 [15.4–15.5] |
| 100 clients: saturated POST p50 ms | 14.0 [13.9–14.1] |
| 500 clients: subscribed | 500 [500–500] |
| 500 clients: connect+subscribe all (s) | 2.54 [2.49–2.59] |
| 500 clients: paced post→one client p50 ms | 24.9 [23.8–25.9] |
| 500 clients: paced post→all clients p50 ms | 27.0 [25.6–28.4] |
| 500 clients: paced post→all clients p99 ms | 37.2 [36.4–38.1] |
| 500 clients: max sustained msgs/s (delivered to all) | 132 [132–133] |
| 500 clients: deliveries/s (client×message) | 66,041 [65,799–66,283] |
| 500 clients: saturated post→all p50 ms | 30.3 [30.3–30.4] |
| 500 clients: saturated POST p50 ms | 29.9 [29.8–30.0] |
| 1000 clients: subscribed | 1,000 [1,000–1,000] |
| 1000 clients: connect+subscribe all (s) | 5.23 [5.18–5.28] |
| 1000 clients: paced post→one client p50 ms | 30.1 [29.9–30.4] |
| 1000 clients: paced post→all clients p50 ms | 34.5 [33.3–35.7] |
| 1000 clients: paced post→all clients p99 ms | 52.0 [51.6–52.4] |
| 1000 clients: max sustained msgs/s (delivered to all) | 79.2 [78.7–79.7] |
| 1000 clients: deliveries/s (client×message) | 79,222 [78,739–79,704] |
| 1000 clients: saturated post→all p50 ms | 49.4 [49.2–49.7] |
| 1000 clients: saturated POST p50 ms | 49.6 [49.2–50.1] |

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
| 100 clients, all subscribed, idle: app process Pss | 526 [517–535] |
| 100 clients, all subscribed, idle: app process RssAnon | 459 [450–468] |
| 100 clients, all subscribed, idle: serving processes Pss | 610 [598–623] |
| 100 clients, all subscribed, idle: whole container Pss | 610 [598–623] |
| 100 clients, saturated fan-out: app process Pss | 529 [518–539] |
| 100 clients, saturated fan-out: app process RssAnon | 468 [457–478] |
| 100 clients, saturated fan-out: serving processes Pss | 614 [600–628] |
| 100 clients, saturated fan-out: whole container Pss | 613 [599–627] |
| 500 clients, all subscribed, idle: app process Pss | 1,219 [1,189–1,249] |
| 500 clients, all subscribed, idle: app process RssAnon | 1,158 [1,128–1,188] |
| 500 clients, all subscribed, idle: serving processes Pss | 1,304 [1,278–1,331] |
| 500 clients, all subscribed, idle: whole container Pss | 1,305 [1,278–1,331] |
| 500 clients, saturated fan-out: app process Pss | 1,282 [1,262–1,303] |
| 500 clients, saturated fan-out: app process RssAnon | 1,221 [1,201–1,242] |
| 500 clients, saturated fan-out: serving processes Pss | 1,371 [1,356–1,387] |
| 500 clients, saturated fan-out: whole container Pss | 1,369 [1,351–1,386] |
| 1000 clients, all subscribed, idle: app process Pss | 2,058 [1,957–2,160] |
| 1000 clients, all subscribed, idle: app process RssAnon | 1,998 [1,896–2,099] |
| 1000 clients, all subscribed, idle: serving processes Pss | 2,146 [2,048–2,244] |
| 1000 clients, all subscribed, idle: whole container Pss | 2,146 [2,048–2,244] |
| 1000 clients, saturated fan-out: app process Pss | 2,161 [2,089–2,233] |
| 1000 clients, saturated fan-out: app process RssAnon | 2,100 [2,029–2,172] |
| 1000 clients, saturated fan-out: serving processes Pss | 2,249 [2,181–2,317] |
| 1000 clients, saturated fan-out: whole container Pss | 2,249 [2,181–2,316] |

### Postgres share of CPU (this port)

`CPU µs/success` above is app + Postgres; the Postgres container's part follows.

| Metric | campfire |
|---|---|
| room_show c=64 Postgres CPU µs/success | 630 [625–635] |
| messages_page c=64 Postgres CPU µs/success | 393 [390–395] |
| search c=64 Postgres CPU µs/success | 161 [161–162] |
| avatar c=64 Postgres CPU µs/success | 58.1 [58.1–58.1] |
| static_css c=64 Postgres CPU µs/success | 0.01 [0.01–0.02] |
| up c=64 Postgres CPU µs/success | 0.01 [0.01–0.01] |
| post_message c=64 Postgres CPU µs/success | 777 [756–797] |

### Background jobs at the end of each rep (Oban)

- campfire rep 1: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
- campfire rep 2: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
