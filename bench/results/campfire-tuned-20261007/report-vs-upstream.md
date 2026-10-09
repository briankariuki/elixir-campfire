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

Reps: campfire 2, upstream reference 2, upstream elixir 2, upstream go 2, upstream rust 2. Cells: median [min–max]. Ratios: this port's advantage (> 1 better).

### Startup and memory

Memory is the sum of the app and Postgres containers for this port (per-container splits are in the raw JSON).

| Metric | campfire (this port) | Rails (upstream) | Elixir (upstream) | Go (upstream) | Rust (upstream) | vs Rails (upstream) | vs Elixir (upstream) | Like-for-like |
|---|---|---|---|---|---|---|---|---|
| cold start: docker run → /up 200 (ms) | 1,225 [1,134–1,316] | 2,601 [2,575–2,627] | 530 [523–536] | 145 [143–147] | 177 [167–187] | 2.1× | 0.4× | ~ |
| idle memory.current (MiB) | 550 [530–569] | 298 [297–298] | 152 [150–153] | 15.5 [9.0–22.0] | 32.0 [15.0–49.0] | 0.5× | 0.3× | ~ |
| idle anon (MiB) | 292 [280–304] | 278 [278–278] | 116 [115–118] | 8.00 [8.00–8.00] | 13.0 [13.0–13.0] | 1.0× | 0.4× | ~ |
| peak memory.current under load (MiB) | 2,300 [2,237–2,362] | 1,458 [1,433–1,484] | 631 [609–653] | 399 [389–409] | 388 [371–406] | 0.6× | 0.3× | ~ |
| peak anon under load (MiB) | 2,164 [2,107–2,222] | 1,419 [1,393–1,445] | 564 [545–583] | 349 [347–351] | 268 [268–269] | 0.7× | 0.3× | ~ |

### HTTP (signed in; keep-alive; c = concurrent connections)

Signed in as David for session routes; `messages_page` and `post_message` use the bot API (no session).

| Metric | campfire (this port) | Rails (upstream) | Elixir (upstream) | Go (upstream) | Rust (upstream) | vs Rails (upstream) | vs Elixir (upstream) | Like-for-like |
|---|---|---|---|---|---|---|---|---|
| room_show c=1 req/s | 120 [119–120] | 90.0 [89.4–90.6] | 292 [292–292] | 990 [987–992] | 8,711 [8,706–8,717] | 1.3× | 0.4× | ~ |
| room_show c=1 p50 ms | 8.20 [8.18–8.22] | 10.6 [10.5–10.7] | 3.38 [3.37–3.39] | 1.00 [0.99–1.00] | 0.11 [0.11–0.11] | 1.3× | 0.4× | ~ |
| room_show c=1 p99 ms | 11.7 [11.5–12.0] | 14.0 [13.6–14.4] | 3.99 [3.94–4.03] | 1.31 [1.30–1.31] | 0.20 [0.19–0.21] | 1.2× | 0.3× | ~ |
| room_show c=1 CPU µs/success | 9,759 [9,658–9,860] | 11,190 [11,119–11,260] | 4,595 [4,329–4,861] | 1,027 [1,024–1,031] | 108 [108–108] | 1.1× | 0.5× | ~ |
| room_show c=16 req/s | 456 [454–458] | 216 [215–216] | 722 [718–726] | 3,860 [3,853–3,868] | 36,260 [36,233–36,287] | 2.1× | 0.6× | ~ |
| room_show c=16 p50 ms | 33.3 [33.3–33.3] | 69.2 [68.7–69.6] | 21.9 [21.7–22.0] | 3.41 [3.35–3.47] | 0.43 [0.43–0.43] | 2.1× | 0.7× | ~ |
| room_show c=16 p99 ms | 87.1 [86.8–87.5] | 173 [173–174] | 31.2 [31.1–31.2] | 12.8 [12.7–12.9] | 0.80 [0.80–0.80] | 2.0× | 0.4× | ~ |
| room_show c=16 CPU µs/success | 8,450 [8,384–8,515] | 14,292 [14,206–14,379] | 4,760 [4,730–4,790] | 1,007 [1,005–1,009] | 103 [103–103] | 1.7× | 0.6× | ~ |
| room_show c=64 req/s | 460 [457–462] | 190 [182–197] | 751 [750–752] | 3,810 [3,791–3,829] | 36,984 [36,948–37,020] | 2.4× | 0.6× | ~ |
| room_show c=64 p50 ms | 139 [138–140] | 367 [316–417] | 84.4 [84.0–84.7] | 14.0 [13.7–14.3] | 1.68 [1.68–1.69] | 2.6× | 0.6× | ~ |
| room_show c=64 p99 ms | 189 [188–190] | 474 [400–548] | 108 [106–111] | 60.5 [58.7–62.3] | 3.09 [3.07–3.10] | 2.5× | 0.6× | ~ |
| room_show c=64 CPU µs/success | 8,201 [8,116–8,285] | 15,972 [15,327–16,617] | 4,674 [4,671–4,676] | 1,019 [1,013–1,025] | 101 [101–101] | 1.9× | 0.6× | ~ |
| messages_page c=1 req/s | 120 [118–122] | 173 [172–174] | 407 [404–410] | 1,365 [1,362–1,368] | 10,352 [10,229–10,475] | 0.7× | 0.3× | x |
| messages_page c=1 p50 ms | 7.77 [7.75–7.78] | 5.61 [5.58–5.63] | 2.43 [2.42–2.45] | 0.72 [0.72–0.72] | 0.09 [0.09–0.09] | 0.7× | 0.3× | x |
| messages_page c=1 p99 ms | 14.5 [14.4–14.6] | 7.80 [7.77–7.83] | 2.98 [2.87–3.09] | 0.99 [0.98–0.99] | 0.17 [0.17–0.17] | 0.5× | 0.2× | x |
| messages_page c=1 CPU µs/success | 10,851 [10,797–10,906] | 5,854 [5,831–5,877] | 3,121 [3,016–3,226] | 741 [740–743] | 91.2 [90.1–92.4] | 0.5× | 0.3× | x |
| messages_page c=16 req/s | 519 [513–524] | 384 [378–389] | 1,053 [1,043–1,063] | 5,573 [5,554–5,591] | 40,872 [40,824–40,919] | 1.4× | 0.5× | x |
| messages_page c=16 p50 ms | 29.2 [29.1–29.3] | 38.9 [38.2–39.6] | 15.0 [14.9–15.2] | 2.18 [2.13–2.23] | 0.38 [0.38–0.38] | 1.3× | 0.5× | x |
| messages_page c=16 p99 ms | 76.0 [73.9–78.1] | 112 [105–119] | 23.1 [22.8–23.5] | 9.05 [8.98–9.12] | 0.67 [0.67–0.67] | 1.5× | 0.3× | x |
| messages_page c=16 CPU µs/success | 7,457 [7,378–7,536] | 7,936 [7,839–8,033] | 3,364 [3,348–3,380] | 697 [695–699] | 91.0 [90.9–91.2] | 1.1× | 0.5× | x |
| messages_page c=64 req/s | 523 [521–526] | 378 [377–379] | 1,031 [1,028–1,035] | 5,461 [5,460–5,462] | 41,995 [41,496–42,494] | 1.4× | 0.5× | x |
| messages_page c=64 p50 ms | 121 [121–121] | 173 [166–180] | 61.7 [61.5–62.0] | 8.48 [8.41–8.55] | 1.49 [1.47–1.51] | 1.4× | 0.5× | x |
| messages_page c=64 p99 ms | 187 [183–190] | 266 [252–280] | 73.7 [73.2–74.2] | 50.2 [50.0–50.4] | 2.59 [2.56–2.61] | 1.4× | 0.4× | x |
| messages_page c=64 CPU µs/success | 7,349 [7,291–7,407] | 7,952 [7,925–7,978] | 3,449 [3,436–3,462] | 711 [711–712] | 88.5 [87.5–89.6] | 1.1× | 0.5× | x |
| sidebar c=1 req/s | – | 195 [177–213] | 855 [846–864] | 5,033 [5,029–5,037] | 7,976 [7,974–7,977] | – | – | x |
| sidebar c=1 p50 ms | – | 4.51 [4.50–4.53] | 1.15 [1.14–1.16] | 0.19 [0.19–0.19] | 0.12 [0.12–0.12] | – | – | x |
| sidebar c=1 p99 ms | – | 14.3 [6.9–21.7] | 1.46 [1.41–1.51] | 0.35 [0.34–0.36] | 0.22 [0.21–0.22] | – | – | x |
| sidebar c=1 CPU µs/success | – | 5,217 [4,735–5,699] | 1,869 [1,851–1,887] | 212 [212–213] | 118 [118–118] | – | – | x |
| sidebar c=16 req/s | – | 503 [489–518] | 1,275 [1,270–1,280] | 19,753 [19,554–19,953] | 34,672 [34,590–34,756] | – | – | x |
| sidebar c=16 p50 ms | – | 30.0 [30.0–30.1] | 12.4 [12.3–12.5] | 0.67 [0.67–0.68] | 0.44 [0.44–0.45] | – | – | x |
| sidebar c=16 p99 ms | – | 79.3 [58.7–99.8] | 17.2 [17.0–17.4] | 2.61 [2.58–2.64] | 0.86 [0.85–0.86] | – | – | x |
| sidebar c=16 CPU µs/success | – | 5,794 [5,634–5,953] | 2,489 [2,486–2,492] | 186 [185–188] | 109 [109–109] | – | – | x |
| sidebar c=64 req/s | – | 514 [502–527] | 1,329 [1,319–1,338] | 19,732 [19,617–19,848] | 35,968 [35,655–36,282] | – | – | x |
| sidebar c=64 p50 ms | – | 130 [119–141] | 48.1 [47.7–48.4] | 3.10 [3.08–3.13] | 1.73 [1.71–1.74] | – | – | x |
| sidebar c=64 p99 ms | – | 169 [153–186] | 57.5 [57.4–57.5] | 6.26 [6.25–6.27] | 3.28 [3.26–3.30] | – | – | x |
| sidebar c=64 CPU µs/success | – | 5,639 [5,519–5,759] | 2,436 [2,426–2,447] | 188 [187–189] | 105 [104–106] | – | – | x |
| search c=1 req/s | 321 [316–326] | 172 [170–173] | 608 [604–611] | 1,762 [1,754–1,771] | 9,721 [9,655–9,786] | 1.9× | 0.5× | ~ |
| search c=1 p50 ms | 2.96 [2.94–2.99] | 5.64 [5.57–5.72] | 1.62 [1.62–1.62] | 0.55 [0.55–0.56] | 0.10 [0.10–0.10] | 1.9× | 0.5× | ~ |
| search c=1 p99 ms | 6.42 [6.26–6.58] | 8.00 [7.99–8.01] | 2.02 [1.98–2.06] | 0.83 [0.81–0.84] | 0.16 [0.15–0.16] | 1.2× | 0.3× | ~ |
| search c=1 CPU µs/success | 4,061 [4,015–4,108] | 5,838 [5,781–5,896] | 2,301 [2,297–2,306] | 588 [584–592] | 95.9 [95.4–96.4] | 1.4× | 0.6× | ~ |
| search c=16 req/s | 1,394 [1,391–1,397] | 380 [377–383] | 1,156 [1,148–1,164] | 7,053 [7,014–7,092] | 33,299 [33,246–33,353] | 3.7× | 1.2× | ~ |
| search c=16 p50 ms | 11.0 [11.0–11.0] | 40.9 [40.0–41.8] | 13.7 [13.6–13.8] | 1.66 [1.64–1.68] | 0.44 [0.44–0.44] | 3.7× | 1.2× | ~ |
| search c=16 p99 ms | 34.0 [23.6–44.4] | 77.0 [68.4–85.6] | 18.8 [18.5–19.0] | 7.57 [7.43–7.71] | 1.02 [1.02–1.03] | 2.3× | 0.6× | ~ |
| search c=16 CPU µs/success | 2,774 [2,773–2,775] | 7,616 [7,567–7,665] | 2,815 [2,804–2,826] | 546 [542–549] | 98.8 [98.7–98.8] | 2.7× | 1.0× | ~ |
| search c=64 req/s | 1,398 [1,398–1,398] | 379 [379–379] | 1,162 [1,161–1,162] | 6,971 [6,918–7,024] | 38,533 [38,236–38,830] | 3.7× | 1.2× | ~ |
| search c=64 p50 ms | 45.4 [45.2–45.5] | 169 [169–169] | 55.0 [54.9–55.1] | 8.07 [8.04–8.11] | 1.56 [1.55–1.57] | 3.7× | 1.2× | ~ |
| search c=64 p99 ms | 63.5 [62.6–64.5] | 192 [191–193] | 64.8 [63.5–66.2] | 31.9 [30.5–33.3] | 3.20 [3.15–3.25] | 3.0× | 1.0× | ~ |
| search c=64 CPU µs/success | 2,743 [2,741–2,745] | 7,657 [7,622–7,692] | 2,843 [2,840–2,846] | 552 [548–556] | 88.0 [87.7–88.3] | 2.8× | 1.0× | ~ |
| avatar c=1 req/s | 1,136 [1,125–1,147] | 27,763 [27,460–28,067] | 28,715 [28,414–29,016] | 39,037 [38,974–39,099] | 61,356 [61,208–61,505] | 0.0× | 0.0× | = |
| avatar c=1 p50 ms | 0.83 [0.83–0.83] | 0.03 [0.03–0.03] | 0.03 [0.03–0.03] | 0.02 [0.02–0.02] | 0.01 [0.01–0.01] | 0.0× | 0.0× | = |
| avatar c=1 p99 ms | 1.29 [1.24–1.34] | 0.10 [0.09–0.10] | 0.09 [0.09–0.10] | 0.05 [0.05–0.05] | 0.02 [0.02–0.02] | 0.1× | 0.1× | = |
| avatar c=1 CPU µs/success | 1,114 [1,112–1,115] | 30.3 [29.7–31.0] | 29.2 [28.6–29.7] | 18.9 [18.9–19.0] | 9.22 [9.17–9.27] | 0.0× | 0.0× | = |
| avatar c=16 req/s | 4,193 [4,189–4,196] | 94,703 [94,383–95,023] | 96,970 [96,381–97,558] | 200,856 [200,458–201,255] | 364,915 [364,464–365,366] | 0.0× | 0.0× | = |
| avatar c=16 p50 ms | 3.62 [3.61–3.63] | 0.10 [0.10–0.10] | 0.10 [0.10–0.10] | 0.06 [0.06–0.06] | 0.04 [0.04–0.04] | 0.0× | 0.0× | = |
| avatar c=16 p99 ms | 7.85 [7.82–7.88] | 0.92 [0.90–0.93] | 0.91 [0.91–0.91] | 0.35 [0.35–0.35] | 0.11 [0.11–0.11] | 0.1× | 0.1× | = |
| avatar c=16 CPU µs/success | 887 [886–888] | 31.5 [31.5–31.6] | 30.6 [30.4–30.8] | 16.6 [16.6–16.6] | 8.03 [7.99–8.06] | 0.0× | 0.0× | = |
| avatar c=64 req/s | 4,421 [4,408–4,434] | 76,098 [75,920–76,277] | 78,929 [77,960–79,898] | 202,708 [202,417–202,999] | 408,993 [404,665–413,321] | 0.1× | 0.1× | = |
| avatar c=64 p50 ms | 14.2 [14.2–14.3] | 0.31 [0.31–0.31] | 0.28 [0.28–0.29] | 0.22 [0.22–0.22] | 0.15 [0.15–0.15] | 0.0× | 0.0× | = |
| avatar c=64 p99 ms | 21.5 [20.9–22.0] | 5.05 [5.04–5.06] | 4.92 [4.86–4.97] | 1.49 [1.48–1.50] | 0.33 [0.33–0.33] | 0.2× | 0.2× | = |
| avatar c=64 CPU µs/success | 862 [860–864] | 39.5 [39.5–39.5] | 37.7 [37.2–38.3] | 16.7 [16.7–16.7] | 7.49 [7.39–7.60] | 0.0× | 0.0× | = |
| static_css c=1 req/s | 8,162 [7,891–8,433] | 33,772 [33,589–33,956] | 33,864 [33,592–34,136] | 54,649 [54,643–54,655] | 65,144 [64,867–65,421] | 0.2× | 0.2× | = |
| static_css c=1 p50 ms | 0.11 [0.11–0.12] | 0.03 [0.03–0.03] | 0.03 [0.03–0.03] | 0.02 [0.02–0.02] | 0.01 [0.01–0.01] | 0.2× | 0.2× | = |
| static_css c=1 p99 ms | 0.24 [0.23–0.25] | 0.07 [0.07–0.07] | 0.07 [0.07–0.07] | 0.03 [0.03–0.03] | 0.02 [0.02–0.02] | 0.3× | 0.3× | = |
| static_css c=1 CPU µs/success | 226 [220–233] | 25.7 [25.5–25.8] | 25.5 [25.2–25.8] | 13.4 [13.4–13.4] | 8.95 [8.94–8.96] | 0.1× | 0.1× | = |
| static_css c=16 req/s | 27,650 [27,587–27,713] | 129,639 [127,745–131,532] | 125,904 [124,586–127,223] | 289,554 [288,579–290,529] | 383,609 [379,449–387,768] | 0.2× | 0.2× | = |
| static_css c=16 p50 ms | 0.46 [0.45–0.46] | 0.08 [0.08–0.09] | 0.09 [0.09–0.09] | 0.04 [0.04–0.04] | 0.04 [0.04–0.04] | 0.2× | 0.2× | = |
| static_css c=16 p99 ms | 2.12 [2.09–2.15] | 0.66 [0.65–0.66] | 0.71 [0.68–0.74] | 0.20 [0.20–0.20] | 0.11 [0.10–0.12] | 0.3× | 0.3× | = |
| static_css c=16 CPU µs/success | 134 [134–134] | 24.4 [24.1–24.8] | 24.8 [24.7–24.9] | 11.0 [11.0–11.0] | 7.64 [7.62–7.66] | 0.2× | 0.2× | = |
| static_css c=64 req/s | 31,624 [31,068–32,180] | 106,504 [106,479–106,530] | 105,374 [104,042–106,707] | 295,610 [293,418–297,802] | 425,869 [419,442–432,296] | 0.3× | 0.3× | = |
| static_css c=64 p50 ms | 1.85 [1.80–1.89] | 0.28 [0.28–0.29] | 0.28 [0.28–0.29] | 0.16 [0.16–0.16] | 0.14 [0.14–0.14] | 0.2× | 0.2× | = |
| static_css c=64 p99 ms | 5.21 [5.16–5.25] | 3.52 [3.51–3.54] | 3.53 [3.48–3.58] | 0.98 [0.98–0.98] | 0.33 [0.31–0.35] | 0.7× | 0.7× | = |
| static_css c=64 CPU µs/success | 118 [116–120] | 29.2 [29.1–29.3] | 29.6 [29.5–29.7] | 10.9 [10.9–11.0] | 7.09 [7.04–7.15] | 0.2× | 0.3× | = |
| up c=1 req/s | 12,282 [12,247–12,318] | 1,787 [1,772–1,801] | 4,128 [4,004–4,252] | 33,455 [33,409–33,501] | 40,443 [40,177–40,708] | 6.9× | 3.0× | = |
| up c=1 p50 ms | 0.08 [0.08–0.08] | 0.53 [0.52–0.53] | 0.23 [0.23–0.24] | 0.03 [0.03–0.03] | 0.02 [0.02–0.02] | 6.9× | 3.0× | = |
| up c=1 p99 ms | 0.12 [0.12–0.13] | 1.09 [1.06–1.13] | 0.37 [0.37–0.38] | 0.06 [0.06–0.06] | 0.04 [0.03–0.04] | 8.7× | 3.0× | = |
| up c=1 CPU µs/success | 87.3 [86.2–88.4] | 596 [591–601] | 374 [366–382] | 25.4 [25.3–25.5] | 15.5 [15.5–15.6] | 6.8× | 4.3× | = |
| up c=16 req/s | 43,348 [42,425–44,270] | 4,054 [4,043–4,066] | 8,493 [8,440–8,547] | 154,476 [153,505–155,448] | 230,480 [226,952–234,008] | 10.7× | 5.1× | = |
| up c=16 p50 ms | 0.27 [0.26–0.27] | 3.81 [3.79–3.83] | 1.83 [1.81–1.84] | 0.08 [0.08–0.08] | 0.07 [0.07–0.07] | 14.2× | 6.8× | = |
| up c=16 p99 ms | 1.64 [1.61–1.67] | 7.92 [7.89–7.96] | 4.30 [4.28–4.32] | 0.42 [0.42–0.43] | 0.12 [0.12–0.12] | 4.8× | 2.6× | = |
| up c=16 CPU µs/success | 55.7 [55.7–55.7] | 718 [718–719] | 404 [401–406] | 23.0 [22.9–23.2] | 14.8 [14.5–15.1] | 12.9× | 7.2× | = |
| up c=64 req/s | 44,007 [41,586–46,428] | 4,003 [4,000–4,006] | 8,931 [8,920–8,943] | 154,068 [153,158–154,979] | 231,156 [227,328–234,985] | 11.0× | 4.9× | = |
| up c=64 p50 ms | 1.27 [1.21–1.33] | 15.7 [15.7–15.8] | 6.72 [6.71–6.74] | 0.31 [0.31–0.31] | 0.27 [0.26–0.27] | 12.4× | 5.3× | = |
| up c=64 p99 ms | 5.11 [4.87–5.34] | 25.9 [25.9–25.9] | 16.6 [16.5–16.6] | 1.74 [1.71–1.76] | 0.56 [0.55–0.57] | 5.1× | 3.2× | = |
| up c=64 CPU µs/success | 58.4 [57.1–59.7] | 732 [732–733] | 398 [397–399] | 23.1 [23.0–23.2] | 14.8 [14.6–15.0] | 12.5× | 6.8× | = |
| post_message c=1 req/s | 220 [214–226] | 140 [139–141] | 413 [413–414] | 1,655 [1,651–1,660] | 2,816 [2,797–2,835] | 1.6× | 0.5× | x |
| post_message c=1 p50 ms | 4.47 [4.37–4.58] | 6.67 [6.64–6.70] | 2.30 [2.29–2.30] | 0.52 [0.52–0.52] | 0.32 [0.32–0.32] | 1.5× | 0.5× | x |
| post_message c=1 p99 ms | 6.67 [6.25–7.10] | 13.3 [13.1–13.5] | 7.76 [7.72–7.81] | 3.53 [3.52–3.55] | 1.64 [1.64–1.65] | 2.0× | 1.2× | x |
| post_message c=1 CPU µs/success | 4,199 [3,985–4,413] | 9,532 [9,527–9,537] | 4,666 [4,626–4,705] | 618 [618–618] | 373 [371–375] | 2.3× | 1.1× | x |
| post_message c=16 req/s | 362 [362–362] | 267 [265–268] | 801 [798–804] | 4,767 [4,750–4,784] | 6,896 [6,864–6,927] | 1.4× | 0.5× | x |
| post_message c=16 p50 ms | 38.0 [38.0–38.1] | 57.3 [56.1–58.6] | 19.4 [19.3–19.6] | 2.18 [2.15–2.21] | 2.04 [2.03–2.06] | 1.5× | 0.5× | x |
| post_message c=16 p99 ms | 125 [124–127] | 158 [151–165] | 26.9 [26.6–27.1] | 12.8 [12.8–12.8] | 5.89 [5.83–5.94] | 1.3× | 0.2× | x |
| post_message c=16 CPU µs/success | 4,146 [4,094–4,199] | 12,340 [12,317–12,364] | 3,841 [3,821–3,861] | 570 [568–572] | 385 [383–386] | 3.0× | 0.9× | x |
| post_message c=64 req/s | 376 [374–377] | 264 [263–264] | 861 [853–868] | 4,660 [4,613–4,708] | 6,801 [6,764–6,837] | 1.4× | 0.4× | x |
| post_message c=64 p50 ms | 160 [158–162] | 233 [229–236] | 74.4 [73.7–75.1] | 10.2 [10.1–10.3] | 9.08 [9.04–9.13] | 1.5× | 0.5× | x |
| post_message c=64 p99 ms | 265 [249–280] | 368 [366–371] | 83.1 [80.5–85.8] | 59.7 [59.3–60.1] | 14.5 [14.4–14.6] | 1.4× | 0.3× | x |
| post_message c=64 CPU µs/success | 3,985 [3,958–4,013] | 12,542 [12,485–12,599] | 3,602 [3,571–3,633] | 578 [577–580] | 392 [391–394] | 3.1× | 0.9× | x |

### HTTP errors / non-2xx-3xx (first rep, per app)

- campfire: none
- skipped workload `sidebar`: no HTTP endpoint in this app: LiveView renders the sidebar inside the page/socket

### LiveView fan-out, one room, one signed-in user (upstream columns: Action Cable, chatter.js subscriptions per client)

| Metric | campfire (this port) | Rails (upstream) | Elixir (upstream) | Go (upstream) | Rust (upstream) | vs Rails (upstream) | vs Elixir (upstream) | Like-for-like |
|---|---|---|---|---|---|---|---|---|
| 100 clients: subscribed | 100 [100–100] | 100 [100–100] | 100 [100–100] | 100 [100–100] | 100 [100–100] | 1.0× | 1.0× | x |
| 100 clients: connect+subscribe all (s) | 0.59 [0.57–0.61] | 0.27 [0.27–0.27] | 0.06 [0.06–0.06] | 0.06 [0.06–0.06] | 0.06 [0.06–0.06] | 0.5× | 0.1× | x |
| 100 clients: paced post→one client p50 ms | 17.6 [17.6–17.7] | 14.5 [14.2–14.7] | 3.60 [3.58–3.62] | 2.01 [1.97–2.04] | 1.73 [1.66–1.80] | 0.8× | 0.2× | x |
| 100 clients: paced post→all clients p50 ms | 18.7 [18.6–18.8] | 20.1 [20.0–20.2] | 4.03 [4.02–4.04] | 2.38 [2.37–2.38] | 1.99 [1.93–2.05] | 1.1× | 0.2× | x |
| 100 clients: paced post→all clients p99 ms | 25.3 [25.0–25.5] | 56.2 [32.4–79.9] | 25.4 [10.3–40.6] | 11.1 [7.7–14.5] | 3.96 [2.62–5.30] | 2.2× | 1.0× | x |
| 100 clients: max sustained msgs/s (delivered to all) | 277 [275–278] | 76.6 [75.7–77.5] | 413 [411–414] | 1,804 [1,802–1,806] | 3,861 [3,828–3,894] | 3.6× | 0.7× | x |
| 100 clients: deliveries/s (client×message) | 27,673 [27,503–27,843] | 7,662 [7,573–7,752] | 41,278 [41,116–41,440] | 180,410 [180,195–180,626] | 386,068 [382,771–389,365] | 3.6× | 0.7× | x |
| 100 clients: saturated post→all p50 ms | 15.5 [15.4–15.5] | 50.2 [48.8–51.6] | 8.00 [7.94–8.06] | 3.46 [3.41–3.52] | 1.17 [1.17–1.18] | 3.2× | 0.5× | x |
| 100 clients: saturated POST p50 ms | 14.0 [13.9–14.1] | 42.4 [38.3–46.5] | 9.29 [9.24–9.34] | 1.90 [1.90–1.90] | 0.89 [0.88–0.89] | 3.0× | 0.7× | x |
| 500 clients: subscribed | 500 [500–500] | 500 [500–500] | 500 [500–500] | 500 [500–500] | 500 [500–500] | 1.0× | 1.0× | x |
| 500 clients: connect+subscribe all (s) | 2.54 [2.49–2.59] | 0.79 [0.77–0.80] | 0.20 [0.18–0.21] | 0.11 [0.11–0.12] | 0.12 [0.12–0.13] | 0.3× | 0.1× | x |
| 500 clients: paced post→one client p50 ms | 24.9 [23.8–25.9] | 28.0 [27.8–28.3] | 7.98 [7.89–8.07] | 3.83 [3.79–3.86] | 2.69 [2.63–2.74] | 1.1× | 0.3× | x |
| 500 clients: paced post→all clients p50 ms | 27.0 [25.6–28.4] | 57.0 [54.9–59.2] | 11.0 [10.8–11.1] | 5.31 [5.26–5.37] | 3.84 [3.73–3.95] | 2.1× | 0.4× | x |
| 500 clients: paced post→all clients p99 ms | 37.2 [36.4–38.1] | 109 [91–127] | 14.7 [12.7–16.8] | 14.3 [10.2–18.4] | 5.30 [5.01–5.59] | 2.9× | 0.4× | x |
| 500 clients: max sustained msgs/s (delivered to all) | 132 [132–133] | 20.9 [20.7–21.2] | 121 [121–122] | 468 [461–475] | 1,086 [1,085–1,088] | 6.3× | 1.1× | x |
| 500 clients: deliveries/s (client×message) | 66,041 [65,799–66,283] | 10,482 [10,360–10,604] | 60,592 [60,333–60,850] | 233,966 [230,416–237,516] | 543,175 [542,363–543,987] | 6.3× | 1.1× | x |
| 500 clients: saturated post→all p50 ms | 30.3 [30.3–30.4] | 966 [150–1,782] | 29.0 [28.6–29.4] | 20.8 [20.4–21.2] | 8.07 [8.02–8.13] | 31.8× | 1.0× | x |
| 500 clients: saturated POST p50 ms | 29.9 [29.8–30.0] | 144 [116–173] | 32.8 [32.8–32.8] | 7.00 [6.94–7.06] | 3.40 [3.39–3.42] | 4.8× | 1.1× | x |
| 1000 clients: subscribed | 1,000 [1,000–1,000] | 1,000 [1,000–1,000] | 1,000 [1,000–1,000] | 1,000 [1,000–1,000] | 1,000 [1,000–1,000] | 1.0× | 1.0× | x |
| 1000 clients: connect+subscribe all (s) | 5.23 [5.18–5.28] | 1.50 [1.49–1.50] | 0.40 [0.38–0.42] | 0.17 [0.14–0.20] | 0.12 [0.11–0.13] | 0.3× | 0.1× | x |
| 1000 clients: paced post→one client p50 ms | 30.1 [29.9–30.4] | 43.3 [40.2–46.4] | 10.6 [10.5–10.8] | 5.90 [5.78–6.03] | 3.98 [3.95–4.01] | 1.4× | 0.4× | x |
| 1000 clients: paced post→all clients p50 ms | 34.5 [33.3–35.7] | 135 [84–185] | 18.3 [18.2–18.3] | 9.39 [9.28–9.51] | 6.24 [6.19–6.30] | 3.9× | 0.5× | x |
| 1000 clients: paced post→all clients p99 ms | 52.0 [51.6–52.4] | 188 [173–204] | 21.7 [21.3–22.1] | 15.9 [12.0–19.7] | 8.48 [8.37–8.59] | 3.6× | 0.4× | x |
| 1000 clients: max sustained msgs/s (delivered to all) | 79.2 [78.7–79.7] | 12.4 [11.9–12.9] | 60.2 [59.7–60.8] | 239 [239–240] | 546 [543–548] | 6.4× | 1.3× | x |
| 1000 clients: deliveries/s (client×message) | 79,222 [78,739–79,704] | 12,412 [11,923–12,901] | 60,219 [59,666–60,772] | 239,119 [238,557–239,681] | 545,654 [543,303–548,006] | 6.4× | 1.3× | x |
| 1000 clients: saturated post→all p50 ms | 49.4 [49.2–49.7] | 879 [325–1,434] | 58.7 [58.6–58.8] | 39.6 [38.4–40.7] | 16.0 [15.9–16.0] | 17.8× | 1.2× | x |
| 1000 clients: saturated POST p50 ms | 49.6 [49.2–50.1] | 209 [196–223] | 66.6 [66.1–67.0] | 15.2 [15.2–15.2] | 7.02 [6.95–7.09] | 4.2× | 1.3× | x |

### Upload + thumbnail (black_hole.jpg, 505 KB)

| Metric | campfire (this port) | Rails (upstream) | Elixir (upstream) | Go (upstream) | Rust (upstream) | vs Rails (upstream) | vs Elixir (upstream) | Like-for-like |
|---|---|---|---|---|---|---|---|---|
| POST with attachment (ms) | – | 57.5 [55.5–59.4] | 92.2 [88.8–95.7] | 28.1 [27.6–28.5] | 28.0 [27.5–28.5] | – | – | ~ |
| then GET thumb → 200 (ms) | – | 0.40 [0.40–0.40] | 0.40 [0.40–0.40] | 0.30 [0.30–0.30] | 0.30 [0.30–0.30] | – | – | ~ |
| POST → thumbnail served (ms) | – | 57.8 [55.8–59.8] | 92.6 [89.1–96.1] | 28.4 [27.9–28.8] | 28.3 [27.8–28.8] | – | – | ~ |

### Memory during fan-out, by process (MiB, peak within the phase)

App process: this port's BEAM; Rails Puma; Elixir's BEAM; Go/Rust's integrated process. Serving totals add Postgres (this port)
or Redis, native helpers and Thruster (upstream). PSS apportions shared pages; RssAnon counts them in each process.

| Metric | campfire (this port) | Rails (upstream) | Elixir (upstream) | Go (upstream) | Rust (upstream) | vs Rails (upstream) | vs Elixir (upstream) | Like-for-like |
|---|---|---|---|---|---|---|---|---|
| 100 clients, all subscribed, idle: app process Pss | 526 [517–535] | 546 [544–547] | 231 [228–234] | 139 [137–141] | 122 [122–122] | 1.0× | 0.4× | x |
| 100 clients, all subscribed, idle: app process RssAnon | 459 [450–468] | 692 [692–693] | 187 [184–190] | 117 [115–119] | 100 [100–101] | 1.5× | 0.4× | x |
| 100 clients, all subscribed, idle: serving processes Pss | 610 [598–623] | 580 [578–581] | 284 [281–288] | 139 [137–141] | 122 [122–122] | 1.0× | 0.5× | x |
| 100 clients, all subscribed, idle: whole container Pss | 610 [598–623] | 851 [848–854] | 284 [280–288] | 139 [137–141] | 122 [122–122] | 1.4× | 0.5× | x |
| 100 clients, saturated fan-out: app process Pss | 529 [518–539] | 646 [644–647] | 356 [355–356] | 139 [136–142] | 121 [120–122] | 1.2× | 0.7× | x |
| 100 clients, saturated fan-out: app process RssAnon | 468 [457–478] | 792 [791–792] | 309 [309–310] | 116 [114–119] | 99.2 [98.4–100.0] | 1.7× | 0.7× | x |
| 100 clients, saturated fan-out: serving processes Pss | 614 [600–628] | 691 [690–693] | 432 [432–432] | 139 [136–142] | 121 [120–122] | 1.1× | 0.7× | x |
| 100 clients, saturated fan-out: whole container Pss | 613 [599–627] | 964 [961–967] | 432 [432–433] | 139 [136–142] | 121 [120–122] | 1.6× | 0.7× | x |
| 500 clients, all subscribed, idle: app process Pss | 1,219 [1,189–1,249] | 617 [617–617] | 363 [360–365] | 141 [138–144] | 118 [117–118] | 0.5× | 0.3× | x |
| 500 clients, all subscribed, idle: app process RssAnon | 1,158 [1,128–1,188] | 762 [760–764] | 316 [314–318] | 119 [116–123] | 96.0 [95.5–96.5] | 0.7× | 0.3× | x |
| 500 clients, all subscribed, idle: serving processes Pss | 1,304 [1,278–1,331] | 680 [680–680] | 456 [455–458] | 141 [138–144] | 118 [117–118] | 0.5× | 0.3× | x |
| 500 clients, all subscribed, idle: whole container Pss | 1,305 [1,278–1,331] | 953 [952–954] | 458 [456–459] | 141 [138–144] | 118 [117–118] | 0.7× | 0.4× | x |
| 500 clients, saturated fan-out: app process Pss | 1,282 [1,262–1,303] | 784 [761–807] | 377 [371–383] | 170 [170–170] | 118 [118–118] | 0.6× | 0.3× | x |
| 500 clients, saturated fan-out: app process RssAnon | 1,221 [1,201–1,242] | 928 [903–953] | 331 [325–336] | 148 [148–149] | 96.2 [96.0–96.3] | 0.8× | 0.3× | x |
| 500 clients, saturated fan-out: serving processes Pss | 1,371 [1,356–1,387] | 857 [833–881] | 516 [508–524] | 170 [170–170] | 118 [118–118] | 0.6× | 0.4× | x |
| 500 clients, saturated fan-out: whole container Pss | 1,369 [1,351–1,386] | 1,129 [1,106–1,152] | 517 [508–525] | 170 [170–170] | 118 [118–118] | 0.8× | 0.4× | x |
| 1000 clients, all subscribed, idle: app process Pss | 2,058 [1,957–2,160] | 678 [667–689] | 394 [389–399] | 169 [167–170] | 126 [126–126] | 0.3× | 0.2× | x |
| 1000 clients, all subscribed, idle: app process RssAnon | 1,998 [1,896–2,099] | 822 [808–835] | 347 [342–352] | 147 [145–149] | 104 [104–105] | 0.4× | 0.2× | x |
| 1000 clients, all subscribed, idle: serving processes Pss | 2,146 [2,048–2,244] | 792 [782–802] | 546 [533–559] | 169 [167–170] | 126 [126–126] | 0.4× | 0.3× | x |
| 1000 clients, all subscribed, idle: whole container Pss | 2,146 [2,048–2,244] | 1,065 [1,054–1,076] | 547 [534–561] | 169 [167–170] | 126 [126–126] | 0.5× | 0.3× | x |
| 1000 clients, saturated fan-out: app process Pss | 2,161 [2,089–2,233] | 991 [986–995] | 423 [418–429] | 218 [217–219] | 125 [125–126] | 0.5× | 0.2× | x |
| 1000 clients, saturated fan-out: app process RssAnon | 2,100 [2,029–2,172] | 1,135 [1,133–1,137] | 376 [370–382] | 196 [196–196] | 104 [103–104] | 0.5× | 0.2× | x |
| 1000 clients, saturated fan-out: serving processes Pss | 2,249 [2,181–2,317] | 1,112 [1,089–1,135] | 600 [600–601] | 218 [217–219] | 125 [125–126] | 0.5× | 0.3× | x |
| 1000 clients, saturated fan-out: whole container Pss | 2,249 [2,181–2,316] | 1,381 [1,357–1,406] | 600 [600–600] | 218 [217–219] | 125 [125–126] | 0.6× | 0.3× | x |

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

### Comparability notes

Everything under "upstream" is copied unchanged from upstream's published `results/ruby-elixir-go-rust-20261004`
(see `bench/results/upstream-20261004/ATTRIBUTION.md`); only the "this port" column was measured here.

- **Hardware and platform differ.** Upstream ran on an AMD Ryzen AI Max+ 395 (32 threads, 30 GB, Linux 7.2, server CPUs 8-11 and
  load generator CPUs 12-15). This port ran in an OrbStack Linux VM on an Apple M2 Pro (see the env block): the VM's vCPUs are scheduled by
  macOS onto performance and efficiency cores, so "4 pinned vCPUs" is not 4 pinned cores. Treat ratios against upstream as indicative
  (order of magnitude), not as a verdict; the throughput, latency and CPU rows depend on core speed directly.
- **The datastore is a separate process.** Upstream's apps use SQLite (and Redis for the Elixir port and Rails) inside the single pinned
  container. Here Postgres runs in its own container, pinned to the same 4 vCPUs as the app and reached over loopback TCP. Memory and
  `CPU µs/success` for this port are the sum over both containers (the Postgres share is reported separately below), so they are
  comparable in scope to upstream's whole-container numbers, but include Postgres's page cache in `memory.current`.
- **No front proxy.** Upstream's Rails/Elixir ports are measured through Thruster (gzip, static caching); here the release's own server
  answers directly (it gzips dynamic responses itself; `caddy` from `docker-compose.yml` is not in the path). Loopback only: no TLS or NIC cost.
- **`room_show` (~)**: `GET /rooms/<id>` is the same page content (same seed, same busy room), but a LiveView dead render of a different
  HTML shape and size (see the preflight sizes in `*-validation.json` against upstream's); throughput follows payload size.
- **`messages_page` (x)**: upstream fetches an HTML page of older messages. This app has no such endpoint (LiveView pages through the
  socket), so the closest equivalent is the bot API `GET /rooms/<id>/<bot_key>/messages?before=<id>` (JSON, 40 messages, no session).
- **`sidebar`**: skipped, there is no HTTP endpoint (LiveView renders the sidebar); upstream's rows show "–" for this port.
- **`search` (~)**: `GET /searches?q=coffee` renders a LiveView dead render; same query and seed.
- **`avatar`, `static_css`, `up` (=)**: same request, different servers. `avatar` here is the seed user's uploaded JPEG; `static_css` the digested `app.css`.
- **`post_message` (x)**: upstream posts through the signed-in form with CSRF and Turbo; this port's load generator posts through the bot API
  (`POST /rooms/<id>/<bot_key>/messages`, 201), which skips session and CSRF handling.
- **Fan-out (x)**: upstream subscribes clients over Action Cable; this port connects LiveView sockets (Phoenix channel protocol, per-process
  rendering of diffs), so "clients" are not the same kind of object. Posters use the bot API instead of the form POST. As upstream,
  one authenticated user holds many connections: not a distinct-user capacity claim (the distinct-users variant, when run, is separate).
- **`upload` (~)**: bot API multipart `attachment` POST instead of the form POST; the same 505 KB `black_hole.jpg`; the thumbnail check follows this
  app's attachment URL.
- **Process memory**: this port's "app process" is the BEAM; "serving processes" and "whole container" add Postgres.

