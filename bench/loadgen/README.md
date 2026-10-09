# loadgen

HTTP, LiveView and Action Cable load generator for the Campfire benchmark. One command per run, one JSON
object on stdout; `PHASE <name> <unix ms>` lines on stderr (`liveview`, `cable`) so memory samples can be
attributed to phases.

Ported from `bench/loadgen` of [basecamp/once-campfire-elixir](https://github.com/basecamp/once-campfire-elixir)
(MIT, see `LICENSE-UPSTREAM`) and adapted to this app. Rust, hyper + tokio-tungstenite.

```
cargo build --release          # -> target/release/loadgen
cargo test --release           # protocol/parsing unit tests
docker build -t campfire-loadgen .                                   # Linux image (ENTRYPOINT loadgen)
docker build --target bin --output type=local,dest=out .             # or just the binary: out/loadgen
```

Common flags: `--base http://host:port` (always plain `http`), `--user-agent UA` (sent on every request and
websocket handshake; none by default). `LOADGEN_DEBUG=1` prints the first 300 bytes of every websocket frame.

## Commands

| command | purpose |
| --- | --- |
| `login --base B --email E --password P [--spoof-ip IP]` | `{"cookie": "_campfire_key=..."}` |
| `scrape --base B --cookie C --room ID` | `{status, bytes, csrf, live_id, has_session, streams: [], css, js}` |
| `http --base B --cookie C --path P --conc N --duration S` | GET load |
| `http --base B --post-room ID --bot-key K --conc N --duration S` | bot-API POST load (201) |
| `liveview --base B --room ID --bot-key K --clients N ...` | LiveView fan-out (below) |
| `upload --base B --room ID --bot-key K --file F [--cookie C] [--reps 5]` | image upload |
| `cable ...`, `fetch`, `gzip` | unchanged from upstream (`cable` is for the Rails/Rust Campfire's Action Cable; it does not apply to this app) |

### login

`GET /session/new` (reads the hidden `_csrf_token` input; falls back to the `csrf-token` meta tag), then
`POST /session` with `email_address`, `password`, `_csrf_token` (and `authenticity_token`, for the Rails app).
Success is a 302 that sets a cookie. Works against this app and against upstream's apps. The sign-in rate limit
is 10 per 3 minutes **per IP**, so repeated logins from one address get 429. With the app running with
`TRUST_PROXY_HEADERS=1`, `--spoof-ip 10.9.0.1` sends `X-Forwarded-For` so each login has its own bucket.

### http

As upstream. `--post-room` without `--bot-key` posts the Rails/Rust web form (200); with `--bot-key` it posts
`bench write N` to `POST /rooms/:room/:bot_key/messages` (`text/plain`) and counts **201** as success. The
output has a new `ok_status` key (200 or 201); `ok`, `rps` and `statuses` use it, so a harness that asserts
`set(statuses) == {"200"}` must expect `{"201"}` for bot posts.

### liveview

Mirrors `cable`: N clients, each a browser, then a paced latency phase and a closed-loop throughput phase.

Per client: `GET /rooms/:id` with the session cookie (own TCP connection) -> read `<meta name="csrf-token">`
and the LiveView root `<div id="phx-..." data-phx-main data-phx-session=".." data-phx-static="..">` ->
websocket `GET /live/websocket?_csrf_token=<csrf>&_mounts=0&vsn=2.0.0` with the **cookie the page response
left behind** (Phoenix stores the CSRF token in the session, so the first page load rewrites
`_campfire_key`; the join is rejected as `stale` with the old cookie), an `Origin` header and no
subprotocol -> join:

```
["1","1","lv:<phx-id>","phx_join",{"url":"<origin>/rooms/<id>","params":{"_csrf_token":"<csrf>","_mounts":0},
                                    "session":"<data-phx-session>","static":"<data-phx-static>"}]
```

-> wait for `phx_reply` with status `ok` -> every 30 s `[null,"<n>","phoenix","heartbeat",{}]`. Every
`diff` event on the client's topic is scanned for `bmk<digits>z` (the join reply, which carries the page's
history, is not: a previous run's messages would count as deliveries), once per client and marker.
`phx_error`, `phx_close` and redirects end the session; with `--reconnect 1` the client re-joins after 1 s
(`_mounts` + 1, same session tokens), without it the socket is counted as `dropped` (upstream's `cable` also
doesn't reconnect).

Posters use the bot API, `POST /rooms/:room/:bot_key/messages`, body `fanout bmk<seq>z`, 201 expected. The
throughput method is upstream's: `--posters` closed-loop posters for `--tput-secs`, then drain, and
`delivered_msgs_per_sec` is messages delivered to *all* ready clients over the span to the last delivery.

| flag | default | |
| --- | --- | --- |
| `--room ID`, `--bot-key K` | required | `K` is `<id>-<bot_token>`, the bot's key in its API URL |
| `--clients N` | 100 | |
| `--cookie C` | | one user, N connections |
| `--distinct-users FILE` | | `email password` per line (`#` comments); each logs in once (8 at a time); client `i` uses user `i mod n`. Takes precedence over `--cookie` |
| `--spoof-ip 1` | off | with `--distinct-users`: `X-Forwarded-For: 10.x.y.z` per user (needs `TRUST_PROXY_HEADERS=1`, else the 10/3 min sign-in limit allows 10 users) |
| `--origin URL` | `http://<base host:port>` | the `Origin` header and the join `url` host. Production checks the origin's **host** against `PHX_HOST`: run the app with `PHX_HOST=localhost` and use `--base http://localhost:PORT` (or `--origin http://localhost`). Dev has `check_origin: false` |
| `--deflate 1` | 0 | offer `permessage-deflate` as browsers do (hand-rolled client, as upstream). Phoenix only compresses with `websocket: [compress: true]`; the output's `deflate_sockets` says how many sockets got it. The dev endpoint does not |
| `--sources a,b` | | bind each client to one of these local source IPs (round robin; ephemeral-port limit) |
| `--connect-conc N` | 50 | page fetches + joins in flight |
| `--heartbeat-secs S` | 30 | |
| `--reconnect 1` | 0 | |
| `--hold-secs S` | 0 | idle after joining (phases `idle`/`idle_done`), as `cable` |
| `--latency-msgs 30 --interval-ms 200 --tput-secs 15 --posters 4` | | as `cable`; same defaults |

Output (same keys as `cable`; new ones marked +):

```
mode+ "liveview", clients, users+, ready, failed, dropped+, connect_secs, subscriptions_per_client (=1),
deflate+, deflate_sockets+, page+ (room-page GET latency summary), join+ (ws connect -> join ok summary),
errors+ ({reason: count}), latency{messages, complete, post, per_client, all_clients},
throughput{posters, posted, posts_per_sec, complete, delivered_msgs_per_sec, frames_per_sec,
           wire_mb_per_sec, drain_secs, post, per_client, all_clients}
```

`ready` counts clients that joined; `failed` clients that never joined (reasons in `errors`); the run aborts
if none joined. The harness's cable assertions (`ready == clients`, `failed == 0`,
`latency.complete == latency.messages`, `throughput.complete == throughput.posted`) carry over unchanged.

Differences from `cable`'s numbers: `wire_mb_per_sec` is measured without `--deflate` too (text payload plus
frame header; with `--deflate` it is the compressed bytes read off the socket). `frames_per_sec` is marked
deliveries per second, i.e. `diff` events that carried a marker. Delivery latency is wall time from the poster's
send to the client's receipt, which in this app includes the request's own processing (the broadcast is
synchronous in the post), so `post` and `per_client` are close.

### upload

With `--bot-key`: multipart `POST /rooms/:room/:bot_key/messages`, field `attachment` (201, JSON with the
message `id`); with `--cookie` it then fetches `GET /attachments/:id?thumb=1` (200). Output as upstream
(`runs[]: post_status, post_ms, thumb_status, thumb_bytes, thumb_ms, total_ms`, `median_total_ms`) plus
`ok_status`; without `--cookie` only the post is timed. The thumbnail is generated during the request here,
so `post_ms` includes it and `thumb_bytes` equals the original for images too small to need one. Without
`--bot-key` it posts upstream's web form as before.

## Differences from upstream

* Sign-in for Phoenix (`_csrf_token` form input), `scrape` without Action Cable streams / sidebar (`streams`
  stays, empty) and with the LiveView root; asset regexes accept `?vsn=` query strings.
* `Poster` (web form or bot API) shared by `http` and the fan-out phases, which are one function
  (`fanout_measure`) used by `cable` and `liveview`.
* `liveview` mode, `--distinct-users`, `--spoof-ip`, `--origin`; `upload --bot-key`; `http --bot-key`.
* Websocket sockets resolve `localhost` to an IPv4 address (the sockets are IPv4 so `--sources` works);
  upstream took the first address, which on a dual-stack host can be `::1`.
* New dependency: `serde` (for `IgnoredAny`, to read a frame's topic/event without allocating its payload).
* `Dockerfile` for Linux builds, `.dockerignore`, unit tests.
