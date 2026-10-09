# Application benchmarks

A port of the [basecamp/once-campfire-elixir](https://github.com/basecamp/once-campfire-elixir) benchmark
harness (MIT; see `results/upstream-20261004/ATTRIBUTION.md`) to this app (Phoenix LiveView + Ash +
Postgres), so that results can be read next to upstream's published Rails / Elixir / Go / Rust numbers.

`bench/run --apps campfire --reps 2` builds the production image, then for each rep starts a fresh
Postgres and a fresh app container, loads the seed, and measures cold start, idle memory, seven HTTP
routes (upstream's eight minus `sidebar`) at 1/16/64 connections, LiveView fan-out at 100/500/1000 clients, image uploads
and (optionally) a distinct-users fan-out, with container memory sampled throughout.

## One command

```sh
orb start                                   # OrbStack must be running (macOS); on Linux just have docker
bench/seed/import                           # once: bench/seed/default/{campfire.sql,uploads,labels.json}, see seed/README.md
bench/run --apps campfire --reps 2          # -> bench/results/<timestamp>/, report printed at the end
bench/report bench/results/<dir> --with-upstream > bench/results/<dir>/report-with-upstream.md
```

`bench/run --dry-run` checks the prerequisites and prints the route table without starting anything;
`bench/run --prepare-only --reps 1` starts the containers, loads the seed, signs in and runs the response
preflight, then stops (a 10-second end-to-end check of everything except the load).

## Environment: a harness container on OrbStack's Linux engine

Upstream's `bench/run` is a Linux script: it pins with `taskset`/`--cpuset-cpus`, reads `/proc/loadavg`, samples each
container's cgroup (`memory.current`, `memory.stat`, `cpu.stat`) and attributes memory per process from
`/proc/<pid>/smaps_rollup`, all over `--network host`. None of that exists on macOS, so the harness runs inside
OrbStack's Linux VM. On macOS, `bench/run` re-executes itself in a privileged *harness container*
(`bench/lib/harness.Dockerfile`: Debian + python3 + util-linux + the docker CLI) started with

```
--privileged --pid host --cgroupns host --network host --cpuset-cpus 8-9
-v /var/run/docker.sock:... -v /sys/fs/cgroup:/sys/fs/cgroup -v <repo>:<repo>
```

and drives the engine through the mounted socket, so Postgres, the app and the load generator are sibling
containers on the VM's own kernel. Why this instead of `orb create ubuntu campfire-bench`: an OrbStack Linux
machine shares the VM's kernel but has its own cgroup namespace and no docker daemon, so the containers the
engine starts are not visible from it (no cgroup files to sample, no PIDs for `smaps_rollup`); making it work
means installing and running a second dockerd, rebuilding every image inside, and still reading cgroups through a
delegated tree. The harness container sees the engine's cgroups (`/sys/fs/cgroup/docker/<id>`) and PIDs directly,
reuses the images already in OrbStack's engine, needs no machine to create or maintain, and the same script runs
unchanged on a Linux host with docker (no harness is used there). `taskset`, `/proc/loadavg`, `memory.current`,
`memory.stat`, `cpu.stat`, `memory.peak` and `smaps_rollup` were all verified to work inside it.
Repo paths are identical on the Mac and in the VM (OrbStack mounts `/Users`), so bind mounts, `--out` and the
seed work with the same absolute paths; `--out` must therefore be inside the repo.

CPU layout (OrbStack VM: all 10 host cores): server `0-3` (Postgres **and** the app together, upstream's app includes its
datastore in its 4 cores), load generator `4-7`, the harness itself (samplers, polling) `8-9`. While it runs the Mac
is kept awake with `caffeinate`.

## Prerequisites

- macOS with OrbStack running (`orb start`) and its VM at the default 10 CPUs; **give it more memory**:
  `orb config set memory_mib 12288` (then `orb stop && orb start`, which restarts every container; the default 8 GB works for a few hundred clients, but 1000
  LiveView clients take the BEAM to roughly 3.3 GB of anonymous memory plus the load generator). Or Linux with docker.
- Python 3 (stdlib only), the docker CLI. Everything else (harness, `postgres:17`, `campfire-port:bench`,
  `campfire-loadgen:bench`) is built or pulled on first use; `--rebuild` rebuilds the three built images.
- The seed (`bench/seed/import`, which reads the upstream parity seed; see `seed/README.md`).
- Quiet machine: on AC power, no other containers, no builds, Low Power Mode off (the run records power state and load).

## What a rep does

Per rep, per app, never two at once; the order alternates between reps when there is more than one app/variant
(`--apps campfire,tuned=campfire-port:tuned`):

1. Wait for the 1-minute load average to drop below `LOAD_MAX` (up to `LOAD_WAIT_SECS`), record it.
2. Fresh `postgres:17` container (host network, `PORT+1`) and run `/app/bin/migrate` from the app image against it.
3. Load `bench/seed/default/campfire.sql` (`psql`), `VACUUM ANALYZE`, `CHECKPOINT`; copy `bench/seed/default/uploads` into a fresh docker volume that
   is mounted at the app's `UPLOADS_DIR` (a volume, not a Mac bind mount, so upload I/O is VM-local).
   Bench-only seed tweak: the bot API 404s unless the bot is a room member and the seed's bot (`bender`) only
   belongs to the watercooler, so a membership of that bot in `hq` (the write room) is added.
4. `docker run` the app (`/app/bin/server`, `PHX_HOST=localhost`, fixed `SECRET_KEY_BASE`, `TRUST_PROXY_HEADERS` unset,
   `MIX_ENV=prod` from the image, `--init`, host network, pinned to `SERVER_CPUS`) -> poll `/up` every 20 ms:
   **cold start**. (`bin/migrate`'s wall time is recorded separately as `migrate_ms`.)
5. Sleep `IDLE_SECS` (10), read **idle memory** (`memory.current` and `anon`, summed over the app and Postgres cgroups).
6. Sign in as David, scrape the digested `app.css` URL, run the **preflight**: 200 only, non-empty, populated
   (message markup / non-empty JSON, image content type, CSS type, `OK`), one bot POST proves the write path, and the
   busy room has more than 50 messages. Sizes and body hashes go to `<app>-<rep>-validation.json`.
7. **HTTP suite**: per route a 2 s warm-up, then each concurrency in `HTTP_CONCS` for `HTTP_SECS`; zero errors and only
   200s (201 for bot posts) are asserted; CPU µs per successful response comes from `cpu.stat` of both cgroups.
8. **LiveView fan-out** at each `CABLE_CLIENTS` (`CABLE_POSTERS` posters via the bot API, `CABLE_TPUT_SECS` closed-loop
   throughput phase after the paced latency phase), with `bench/lib/procmem.py` sampling per-process Pss/Anonymous by role
   (`beam`, `postgres`) every 250 ms and attributing it to the load generator's `PHASE` markers.
9. **Upload suite** (`UPLOAD_REPS` x `black_hole.jpg`, 505 KB, bot API multipart, then the thumbnail fetch).
10. Peak memory (200 ms sampling of both cgroups, the sum and each), Oban queue counts, then everything is removed.
11. Optional **distinct-users fan-out** (`SUITES="... distinct"`) last, see below.

### Suites and knobs

| Knob | Default | |
|---|---|---|
| `SERVER_CPUS` / `LOADGEN_CPUS` / `PROCMEM_CPUS` | `0-3` / `4-7` / `8-9` | Postgres + app / load generator / the harness |
| `HTTP_SECS`, `HTTP_CONCS` | `8`, `"1 16 64"` | |
| `CABLE_CLIENTS`, `CABLE_POSTERS`, `CABLE_TPUT_SECS` | `"100 500 1000"`, `4`, `15` | LiveView fan-out (names kept from upstream) |
| `UPLOAD_REPS` | `5` | |
| `SUITES` | `"http liveview upload"` | add `distinct`; `cable` is accepted as an alias for `liveview` |
| `DISTINCT_CLIENTS` | `"100 500 1000"` | one user per client |
| `LOAD_MAX`, `LOAD_WAIT_SECS`, `IDLE_SECS` | `1.5`, `900`, `10` | |
| `PORT`, `PG_PORT` | `47130`, `PORT+1` | both on the VM's host network; they must be free |
| `APP_IMAGE`, `PG_IMAGE`, `LOADGEN_IMAGE` | `campfire-port:bench`, `postgres:17`, `campfire-loadgen:bench` | |
| `PG_ARGS`, `APP_EXTRA_ENV`, `APP_EXTRA_ENV_<NAME>` | none | extra `postgres -c ..`; `K=V` for every app / one variant |
| `SEED_DIR`, `SECRET_KEY_BASE` | `bench/seed/default`, fixed | |
| `LIVEVIEW_ARGS` | none | extra `loadgen liveview` flags for the fan-out suites, e.g. `--deflate 1` (recorded in `env.txt`) |
| `BENCH_KEEP` | unset | `1` leaves the containers and the work directory after a rep (with `--prepare-only`: an app with the seed on `PORT`, for poking at it) |

Command line: `--apps NAME[=IMAGE],...` (default `campfire`), `--reps N` (default 4), `--out DIR`, `--user-agent UA`,
`--dry-run`, `--prepare-only`, `--rebuild`. Record every override with the result: `env.txt` does it for you.
`BENCH_KEEP=1` leaves the containers and work directory after a rep for debugging.

Workloads map from upstream's as follows:

| Upstream | Here |
|---|---|
| `room_show` | `GET /rooms/<watercooler>` (signed in; LiveView dead render) |
| `messages_page` | **bot API** `GET /rooms/<id>/<bot_key>/messages?before=<busy_060>`: closest equivalent (JSON, 40 messages, no session) |
| `sidebar` | **skipped**: no HTTP endpoint, LiveView renders it |
| `search` | `GET /searches?q=coffee` |
| `avatar` | `GET /users/<jason>/avatar` (uploaded JPEG) |
| `static_css` | the digested `/assets/app-<digest>.css` found in the room page |
| `up` | `GET /up` |
| `post_message` | **bot API** `POST /rooms/<hq>/<bot_key>/messages` (201) |
| Action Cable fan-out | LiveView fan-out: one signed-in user, N sockets on the busy room; posters via the bot API |
| upload | bot API multipart `attachment` POST, then the thumbnail fetch |
| (none) | distinct-users fan-out |

### Distinct-users fan-out

Upstream's fan-out is one authenticated user with many connections, which is not a many-users claim. With `SUITES="http liveview upload distinct"`
the last step creates `max(DISTINCT_CLIENTS)` members of the busy room by SQL (all with David's bcrypt hash and the
seed password) and runs the fan-out with `--distinct-users` so every client is a different signed-in user. Sign-in is limited to 10 per 3 minutes per IP, so
each user signs in with its own spoofed `X-Forwarded-For`, which the app only honours with `TRUST_PROXY_HEADERS=1`: **this suite runs on a restarted app
container (same data) with that variable set**, after all other suites so they are unaffected. Each user's sign-in is a bcrypt verification (cost 12) on the server's 4 CPUs,
so connecting takes longer than in the single-user run; `connect_secs` reports it.

## Results

One directory per run (`bench/results/<timestamp>/` or `--out`):

| File | |
|---|---|
| `env.txt` | host (Mac model, cores, macOS, OrbStack, power state), the Linux VM, CPU sets, knobs, seed digest (sha256 of `campfire.sql`, `labels.json`, a digest of `uploads/`), **source digest** (git `HEAD` + dirty flag/diff hash over `lib config priv assets rel mix.* Dockerfile`), image IDs (app, Postgres, load generator) |
| `<app>-<rep>.json` | everything the report reads: cold start, memory, `http[]`, `liveview[]`, `distinct[]`, `upload`, pinning, load averages |
| `<app>-<rep>-{http,liveview,distinct,upload}.json` | each suite's raw load generator output (written as the suite finishes) |
| `<app>-<rep>-validation.json` | preflight evidence: status, type, encoding, wire/decoded bytes and body sha256 per route |
| `<app>-<rep>-jobs.json` | Oban queue counts at the end of the rep (upstream records its Resque backlog) |
| `uptime.log`, `report.md` | load before/after each rep; the report |

`bench/report DIR` prints median [min-max] tables in upstream's format and units (and writes `report.md` at the end of a run);
`bench/report DIR --with-upstream [PATH]` adds upstream's published medians (default `results/upstream-20261004`, a copy of its
`ruby-elixir-go-rust-20261004`) as extra columns with advantage ratios and a "Like-for-like" mark per row
(`=` same workload, `~` similar, `x` not comparable) and the notes below. `bench/compare A B` compares two matched runs of the same app
(throughput, latency, cost, CPU per success, job counts) and warns when their knobs differ.

Reading the tables: cells are medians over reps with `[min-max]`; the ratio columns are this port's *advantage* over that column, > 1 meaning better
(higher throughput, lower latency/memory/time). Throughput and latency are closed-loop (c concurrent connections, keep-alive), so latency at c=64 mostly
reflects queueing. `CPU µs/success` is the CPU time of the whole server side (app + Postgres containers) per successful response; the Postgres share is in
its own table. "Max sustained msgs/s (delivered to all)" is the fan-out throughput: messages that reached every client per second.
Two reps are an initial comparison with balanced order; use more reps and longer `HTTP_SECS` before drawing conclusions from small differences.

## Differences from upstream and caveats

- **Hardware.** Upstream: AMD Ryzen AI Max+ 395, 32 threads, bare Linux, CPUs 8-11 / 12-15. Here: Apple M2 Pro (6 performance + 4 efficiency
  cores) through OrbStack's VM. vCPU pinning inside the VM does not pin host cores: macOS schedules the vCPU threads on any core, so efficiency cores,
  thermal limits and other Mac activity add noise. Cross-machine ratios are indicative only; compare runs on this machine with `bench/compare`.
- **Datastore in its own container.** Upstream's apps have SQLite (and Redis) in the one pinned container. Here Postgres runs in a second container pinned to the *same* 4 vCPUs,
  over loopback TCP, with stock configuration (`PG_ARGS` to change). Memory is summed over both (and includes Postgres's page cache in
  `memory.current`; `anon` does not); the seed is only 169 messages, so the working set is tiny and Postgres stays warm.
- **Cold start** is `docker run` of the app to `/up` 200 with the database already running and loaded, like upstream (data copied first); `bin/migrate`
  (which `docker-compose.yml` runs before the server) is not included, its time is in `migrate_ms`.
- **No front proxy, no TLS.** Upstream's Rails and Elixir ports are measured through Thruster. Here the release answers directly (it gzips dynamic
  responses itself; Caddy from `docker-compose.yml` is not in the path). Loopback only; no NIC or TLS cost. `127.0.0.1` is used as the host
  because `config/prod.exs` exempts `localhost` and `127.0.0.1` from `force_ssl`; the load generator sends `Origin: http://localhost` for the sockets (`PHX_HOST=localhost`).
- **Different pages and protocols**: see the mapping table; `messages_page` and `post_message` go through the JSON bot API, the fan-out uses LiveView sockets and
  posters use the bot API instead of the CSRF form. Preflight sizes in `*-validation.json` show how large the responses are; throughput follows them.
- **`sidebar` is skipped** (no endpoint). It is the most Rails-specific upstream row.
- **Seed**: the upstream parity seed converted by `bench/seed/import`: 168 of 169 messages (one has a missing author), plain-text bodies instead of
  Action Text HTML, attachments converted; timestamps are the seed's, the app uses the real clock. Its sha256 does not match upstream's (see `seed/README.md`).
- **Background jobs**: Oban runs in the app; its queue counts are recorded at the end of each rep. The seed itself has no jobs; only jobs triggered by the benchmark's own posts and uploads exist.
- **Single-user fan-out** like upstream; the distinct-users variant is separate and runs on a restarted app (above).
- **Memory in a VM**: `memory.current` includes page cache; peak numbers depend on the VM's memory pressure. If OrbStack's VM runs out of memory the engine
  restarts and the run fails: raise the VM's memory (above) rather than lowering the client counts.
- Results from `--prepare-only` or tiny-knob runs are smoke tests, not benchmarks.

## Files

| Path | |
|---|---|
| `run` | launcher (macOS -> harness container) and the benchmark |
| `lib/benchlib.py`, `lib/suites.py` | docker/cgroup/sampling helpers; the suites, preflight and the workload mapping (`LABEL_KEYS` maps `labels.json`) |
| `lib/procmem.py` | per-process memory by role (adapted from upstream) |
| `lib/harness.Dockerfile`, `lib/fixtures/black_hole.jpg` | the harness image; the upload fixture (from upstream's test fixtures) |
| `report`, `compare`, `lvsum` | tables, upstream comparison; `lvsum DIR...` is a compact fan-out-only side by side (throughput, latency, wire, server CPU per frame) |
| `profile-fanout`, `profile-fanout-analyze` | profile the BEAM of an image under a steady LiveView fan-out (msacc, scheduler wall time, tprof) and summarise it; see `TUNING.md` |
| `lib/dom-check.mjs` | ad hoc headless-Chrome check that the live DOM of room messages is unchanged between two images (needs `playwright-core`) |
| `loadgen/`, `seed/` | the load generator (fork of upstream's) and the seed importer (see their READMEs) |
| `results/upstream-20261004/` | upstream's published comparison, for `--with-upstream` |
| `TUNING.md` | the fan-out profile, what was changed because of it and the before/after numbers |
