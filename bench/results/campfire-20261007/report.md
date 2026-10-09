```
date: 2026-10-07T15:54:32+0000
host: Apple M2 Pro, 10 cores (6 performance + 4 efficiency), 16GB, macOS 26.6.2
host (1): orbstack: Version: 2.1.1 (2010100); VM cpu/memory: cpu: 10 memory_mib: 8192
host (2): power: Now drawing from 'AC Power'  -InternalBattery-0 (id=35192931)	9%; charging; 2:27 remaining present: true; lowpowermode=lowpowermode 0
host (3): host load before: 18:54  up 24 days,  7:40, 3 users, load averages: 2.14 3.46 2.86
linux (where the benchmark runs): 6.19.13-orbstack-gbd1dc07b8cf4 aarch64, cpu model not exposed, 10 vCPUs, 7.8GB (OrbStack VM, harness container)
server cpus: 0-3 (nproc 4; Postgres + app together); loadgen cpus: 4-7; harness cpus: 8-9; network: host
env (app): PORT=47130 PHX_HOST=localhost MIX_ENV=prod (image) TRUST_PROXY_HEADERS=(unset) POOL_SIZE=(default 10) UPLOADS_DIR=/data/uploads APP_EXTRA_ENV=(none)
postgres: postgres:17 port 47131 args: (defaults)
seed sha256: e233c542b4a233f4348888cdd21066d4e3549e868da99755518d5383c974967f  campfire.sql
seed sha256: 089726b88abf5f9baf1bb19b2e86beb83d3105ab976d5e6e50f6265cde324d5e  labels.json
seed sha256: 92e368f1640d4a17c6bc83bfb4f731a3426fdaa562f01f8fa0fa1fd5b45bff27  uploads/ (8 files, names+sizes)
source digest: d29e74ecdae2bbd89a0ddcc5247f0e7ac35a22ca (dirty: 0 files)
workload: suites=http liveview upload HTTP_SECS=4 HTTP_CONCS=1 16 64 CABLE_CLIENTS=100 500 1000 CABLE_TPUT_SECS=15 CABLE_POSTERS=4 DISTINCT_CLIENTS=100 500 1000 UPLOAD_REPS=5 IDLE_SECS=10 REPS=2
quiet wait: LOAD_MAX=1.5 LOAD_WAIT_SECS=30
user agent: (none)
campfire image: campfire-port:bench sha256:5e7a976e1ede695ca1f2b8068222ea5bb670c6bdbb3e5b67bf98f730201bcad2 2026-10-07T07:40:32.656275354+03:00 unpacked_bytes=261533574
postgres image id: sha256:97432f980da100ebd3e419711efee84e1e97a966d62c035286a07f239ddb4d9c 2026-09-19T00:38:59.786253347Z unpacked_bytes=476570430
loadgen image: campfire-loadgen:bench sha256:35d24d2d7e8d395ce7df23196d5c0c4984caa45e16fe64f305c7abab2f76cef2 2026-10-07T07:57:00.714539169+03:00 unpacked_bytes=101186065
```

Reps: campfire 2. Cells: median [min–max].

### Startup and memory

Memory is the sum of the app and Postgres containers for this port (per-container splits are in the raw JSON).

| Metric | campfire |
|---|---|
| cold start: docker run → /up 200 (ms) | 1,340 [1,212–1,468] |
| idle memory.current (MiB) | 524 [505–542] |
| idle anon (MiB) | 279 [275–283] |
| peak memory.current under load (MiB) | 3,369 [3,341–3,397] |
| peak anon under load (MiB) | 3,244 [3,220–3,268] |

### HTTP (signed in; keep-alive; c = concurrent connections)

Signed in as David for session routes; `messages_page` and `post_message` use the bot API (no session).

| Metric | campfire |
|---|---|
| room_show c=1 req/s | 92.5 [91.2–93.7] |
| room_show c=1 p50 ms | 10.4 [10.2–10.6] |
| room_show c=1 p99 ms | 18.1 [14.7–21.5] |
| room_show c=1 CPU µs/success | 12,085 [11,952–12,219] |
| room_show c=16 req/s | 381 [376–385] |
| room_show c=16 p50 ms | 40.3 [39.4–41.2] |
| room_show c=16 p99 ms | 92.0 [84.4–99.6] |
| room_show c=16 CPU µs/success | 10,104 [9,979–10,228] |
| room_show c=64 req/s | 380 [377–383] |
| room_show c=64 p50 ms | 167 [165–169] |
| room_show c=64 p99 ms | 227 [227–228] |
| room_show c=64 CPU µs/success | 9,995 [9,873–10,118] |
| messages_page c=1 req/s | 114 [106–121] |
| messages_page c=1 p50 ms | 8.37 [8.12–8.62] |
| messages_page c=1 p99 ms | 14.2 [11.7–16.7] |
| messages_page c=1 CPU µs/success | 11,405 [11,005–11,804] |
| messages_page c=16 req/s | 490 [480–500] |
| messages_page c=16 p50 ms | 30.7 [30.1–31.3] |
| messages_page c=16 p99 ms | 81.9 [77.5–86.2] |
| messages_page c=16 CPU µs/success | 7,840 [7,722–7,959] |
| messages_page c=64 req/s | 507 [507–508] |
| messages_page c=64 p50 ms | 125 [124–125] |
| messages_page c=64 p99 ms | 201 [198–205] |
| messages_page c=64 CPU µs/success | 7,557 [7,527–7,588] |
| search c=1 req/s | 292 [277–307] |
| search c=1 p50 ms | 3.24 [3.15–3.33] |
| search c=1 p99 ms | 6.65 [6.05–7.24] |
| search c=1 CPU µs/success | 4,422 [4,381–4,464] |
| search c=16 req/s | 1,359 [1,354–1,365] |
| search c=16 p50 ms | 11.3 [11.2–11.4] |
| search c=16 p99 ms | 23.2 [23.1–23.2] |
| search c=16 CPU µs/success | 2,861 [2,843–2,879] |
| search c=64 req/s | 1,342 [1,313–1,372] |
| search c=64 p50 ms | 47.0 [46.0–48.0] |
| search c=64 p99 ms | 68.1 [65.3–71.0] |
| search c=64 CPU µs/success | 2,862 [2,806–2,919] |
| avatar c=1 req/s | 1,035 [1,009–1,061] |
| avatar c=1 p50 ms | 0.91 [0.88–0.93] |
| avatar c=1 p99 ms | 1.54 [1.52–1.56] |
| avatar c=1 CPU µs/success | 1,205 [1,175–1,235] |
| avatar c=16 req/s | 3,932 [3,858–4,006] |
| avatar c=16 p50 ms | 3.84 [3.77–3.92] |
| avatar c=16 p99 ms | 8.47 [8.31–8.62] |
| avatar c=16 CPU µs/success | 924 [908–940] |
| avatar c=64 req/s | 4,135 [4,007–4,264] |
| avatar c=64 p50 ms | 15.2 [14.7–15.7] |
| avatar c=64 p99 ms | 25.6 [22.9–28.2] |
| avatar c=64 CPU µs/success | 896 [886–906] |
| static_css c=1 req/s | 7,563 [7,489–7,636] |
| static_css c=1 p50 ms | 0.12 [0.12–0.12] |
| static_css c=1 p99 ms | 0.28 [0.28–0.28] |
| static_css c=1 CPU µs/success | 240 [239–240] |
| static_css c=16 req/s | 27,110 [26,621–27,598] |
| static_css c=16 p50 ms | 0.48 [0.47–0.49] |
| static_css c=16 p99 ms | 2.08 [2.06–2.10] |
| static_css c=16 CPU µs/success | 136 [134–138] |
| static_css c=64 req/s | 31,142 [30,408–31,876] |
| static_css c=64 p50 ms | 1.86 [1.83–1.89] |
| static_css c=64 p99 ms | 5.29 [5.04–5.55] |
| static_css c=64 CPU µs/success | 119 [118–121] |
| up c=1 req/s | 11,096 [10,994–11,199] |
| up c=1 p50 ms | 0.08 [0.08–0.08] |
| up c=1 p99 ms | 0.15 [0.15–0.16] |
| up c=1 CPU µs/success | 89.6 [88.0–91.3] |
| up c=16 req/s | 41,463 [40,569–42,358] |
| up c=16 p50 ms | 0.29 [0.28–0.29] |
| up c=16 p99 ms | 1.72 [1.69–1.75] |
| up c=16 CPU µs/success | 57.9 [57.0–58.7] |
| up c=64 req/s | 39,990 [38,461–41,519] |
| up c=64 p50 ms | 1.36 [1.29–1.42] |
| up c=64 p99 ms | 5.75 [5.66–5.85] |
| up c=64 CPU µs/success | 62.7 [62.3–63.2] |
| post_message c=1 req/s | 196 [188–203] |
| post_message c=1 p50 ms | 4.97 [4.76–5.18] |
| post_message c=1 p99 ms | 8.02 [7.88–8.15] |
| post_message c=1 CPU µs/success | 4,600 [4,256–4,945] |
| post_message c=16 req/s | 347 [336–357] |
| post_message c=16 p50 ms | 39.4 [38.6–40.2] |
| post_message c=16 p99 ms | 133 [132–134] |
| post_message c=16 CPU µs/success | 4,420 [4,316–4,523] |
| post_message c=64 req/s | 357 [350–364] |
| post_message c=64 p50 ms | 169 [166–172] |
| post_message c=64 p99 ms | 286 [262–310] |
| post_message c=64 CPU µs/success | 4,290 [4,235–4,346] |

### HTTP errors / non-2xx-3xx (first rep, per app)

- campfire: none
- skipped workload `sidebar`: no HTTP endpoint in this app: LiveView renders the sidebar inside the page/socket

### LiveView fan-out, one room, one signed-in user (upstream columns: Action Cable, chatter.js subscriptions per client)

| Metric | campfire |
|---|---|
| 100 clients: subscribed | 100 [100–100] |
| 100 clients: connect+subscribe all (s) | 0.68 [0.66–0.69] |
| 100 clients: paced post→one client p50 ms | 20.1 [18.9–21.3] |
| 100 clients: paced post→all clients p50 ms | 22.5 [21.6–23.4] |
| 100 clients: paced post→all clients p99 ms | 32.9 [31.6–34.2] |
| 100 clients: max sustained msgs/s (delivered to all) | 117 [115–118] |
| 100 clients: deliveries/s (client×message) | 11,658 [11,463–11,852] |
| 100 clients: saturated post→all p50 ms | 33.7 [33.3–34.1] |
| 100 clients: saturated POST p50 ms | 33.4 [33.0–33.8] |
| 500 clients: subscribed | 500 [500–500] |
| 500 clients: connect+subscribe all (s) | 2.83 [2.82–2.85] |
| 500 clients: paced post→one client p50 ms | 38.7 [37.7–39.6] |
| 500 clients: paced post→all clients p50 ms | 44.7 [42.8–46.5] |
| 500 clients: paced post→all clients p99 ms | 114 [110–117] |
| 500 clients: max sustained msgs/s (delivered to all) | 35.5 [34.8–36.1] |
| 500 clients: deliveries/s (client×message) | 17,740 [17,410–18,070] |
| 500 clients: saturated post→all p50 ms | 113 [112–115] |
| 500 clients: saturated POST p50 ms | 111 [109–113] |
| 1000 clients: subscribed | 1,000 [1,000–1,000] |
| 1000 clients: connect+subscribe all (s) | 5.96 [5.92–6.01] |
| 1000 clients: paced post→one client p50 ms | 59.1 [57.2–61.0] |
| 1000 clients: paced post→all clients p50 ms | 70.6 [68.4–72.8] |
| 1000 clients: paced post→all clients p99 ms | 203 [195–211] |
| 1000 clients: max sustained msgs/s (delivered to all) | 19.2 [18.9–19.6] |
| 1000 clients: deliveries/s (client×message) | 19,236 [18,855–19,618] |
| 1000 clients: saturated post→all p50 ms | 209 [203–215] |
| 1000 clients: saturated POST p50 ms | 204 [200–207] |

### Upload + thumbnail (black_hole.jpg, 505 KB)

| Metric | campfire |
|---|---|
| POST with attachment (ms) | 41.4 [39.7–43.0] |
| then GET thumb → 200 (ms) | 2.60 [2.50–2.70] |
| POST → thumbnail served (ms) | 43.8 [42.2–45.4] |

### Memory during fan-out, by process (MiB, peak within the phase)

App process: this port's BEAM; Rails Puma; Elixir's BEAM; Go/Rust's integrated process. Serving totals add Postgres (this port)
or Redis, native helpers and Thruster (upstream). PSS apportions shared pages; RssAnon counts them in each process.

| Metric | campfire |
|---|---|
| 100 clients, all subscribed, idle: app process Pss | 553 [549–558] |
| 100 clients, all subscribed, idle: app process RssAnon | 492 [488–497] |
| 100 clients, all subscribed, idle: serving processes Pss | 637 [636–637] |
| 100 clients, all subscribed, idle: whole container Pss | 637 [636–637] |
| 100 clients, saturated fan-out: app process Pss | 506 [504–509] |
| 100 clients, saturated fan-out: app process RssAnon | 445 [443–448] |
| 100 clients, saturated fan-out: serving processes Pss | 590 [588–592] |
| 100 clients, saturated fan-out: whole container Pss | 590 [588–592] |
| 500 clients, all subscribed, idle: app process Pss | 1,260 [1,245–1,276] |
| 500 clients, all subscribed, idle: app process RssAnon | 1,199 [1,184–1,215] |
| 500 clients, all subscribed, idle: serving processes Pss | 1,344 [1,325–1,364] |
| 500 clients, all subscribed, idle: whole container Pss | 1,344 [1,325–1,364] |
| 500 clients, saturated fan-out: app process Pss | 1,068 [965–1,171] |
| 500 clients, saturated fan-out: app process RssAnon | 1,007 [904–1,110] |
| 500 clients, saturated fan-out: serving processes Pss | 1,152 [1,045–1,259] |
| 500 clients, saturated fan-out: whole container Pss | 1,152 [1,045–1,259] |
| 1000 clients, all subscribed, idle: app process Pss | 2,095 [2,083–2,108] |
| 1000 clients, all subscribed, idle: app process RssAnon | 2,035 [2,022–2,047] |
| 1000 clients, all subscribed, idle: serving processes Pss | 2,181 [2,165–2,198] |
| 1000 clients, all subscribed, idle: whole container Pss | 2,181 [2,165–2,198] |
| 1000 clients, saturated fan-out: app process Pss | 1,736 [1,532–1,939] |
| 1000 clients, saturated fan-out: app process RssAnon | 1,675 [1,471–1,879] |
| 1000 clients, saturated fan-out: serving processes Pss | 1,822 [1,614–2,029] |
| 1000 clients, saturated fan-out: whole container Pss | 1,822 [1,614–2,029] |

### Postgres share of CPU (this port)

`CPU µs/success` above is app + Postgres; the Postgres container's part follows.

| Metric | campfire |
|---|---|
| room_show c=64 Postgres CPU µs/success | 698 [687–708] |
| messages_page c=64 Postgres CPU µs/success | 416 [416–416] |
| search c=64 Postgres CPU µs/success | 174 [166–182] |
| avatar c=64 Postgres CPU µs/success | 63.1 [63.0–63.1] |
| static_css c=64 Postgres CPU µs/success | 0.02 [0.01–0.02] |
| up c=64 Postgres CPU µs/success | 0.01 [0.01–0.02] |
| post_message c=64 Postgres CPU µs/success | 811 [791–830] |

### Background jobs at the end of each rep (Oban)

- campfire rep 1: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
- campfire rep 2: {'queued': 0, 'processed': 0, 'failed': 0, 'states': {}}
