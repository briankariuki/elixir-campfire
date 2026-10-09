# Performance tuning: LiveView message fan-out

Same spirit as upstream's tuning notes (`once-campfire-elixir/bench/TUNING.md`): profile an isolated, warmed release,
fix the biggest cost, measure, keep only what helps. Everything here is on the harness of `bench/README.md` (4 pinned
server cores shared by the app and Postgres, M2 Pro in OrbStack's VM, loopback, no TLS), one room, one signed-in user
with N sockets, messages posted through the bot API. Numbers are medians of 2 reps; rep-to-rep spread is a few percent
(the same image measured twice, minutes apart: 116.5 / 35.5 / 19.2 msgs/s in `campfire-20261007`, 122.3 / 36.8 / 19.6
in `lv-baseline-rerun`).

## Result

Max sustained msgs/s delivered to every client (closed-loop posters, 15 s), p50 of the paced post-to-all latency, peak
memory. Baseline = `results/campfire-20261007`, tuned = `results/campfire-tuned-20261007` (`SUITES="http liveview"`, 2 reps,
`report-vs-upstream.md` and `compare-vs-baseline.md` in that directory).

| | baseline | tuned | |
|---|---:|---:|---:|
| 100 clients, msgs/s | 116.5 | 276.7 | 2.4x |
| 500 clients, msgs/s | 35.5 | 132.1 | 3.7x |
| 1000 clients, msgs/s | 19.2 | 79.2 | 4.1x |
| 500 clients, paced post-to-all p50 / p99 ms | 44.7 / 114 | 27.0 / 37.2 | 0.60x / 0.33x |
| 1000 clients, paced post-to-all p50 / p99 ms | 70.6 / 203 | 34.5 / 52.0 | 0.49x / 0.26x |
| 1000 clients, wire MB/s (it moves 4.1x the frames, each 10% bigger) | 116 | 525 | |
| server CPU per delivered frame, 500 clients, steady load (profile below) | 217 us | 55 us | 0.25x |
| peak anonymous memory, 1000 clients (MiB) | 3,244 | 2,165 | 0.67x |
| `room_show` c=64 req/s (the dead render also uses the new message cache) | 380 | 460 | 1.21x |
| other HTTP routes, c=64 | | | 1.02x to 1.10x (noise to slightly better; none worse) |

Against upstream's published Elixir port on this fan-out (same workload, other hardware, `report-vs-upstream.md`): 0.3x
before, now 1.1x at 500 clients and 1.3x at 1000 (0.7x at 100). Go stays 3x to 6.5x ahead, Rust 7x to 14x.

Per step, each measured with `SUITES=liveview bench/run --reps 2` on an image built for it (`bench/lvsum DIR...` prints
this): max msgs/s at 100 / 500 / 1000 clients.

| step | 100 | 500 | 1000 | kept |
|---|---:|---:|---:|---|
| baseline (re-measured the same day) | 122.3 | 36.8 | 19.6 | |
| 1. Elixir's built-in `JSON` instead of Jason | 127.3 (+4%) | 38.0 (+3%) | 20.7 (+6%) | yes |
| 2. encode each diff once for all viewers (`SocketSerializer`) | 151.9 (+19%) | 57.0 (+50%) | 34.1 (+65%) | yes |
| 3. render each message once for all viewers (`cached_message`) | 202.3 (+33%) | 74.5 (+31%) | 43.5 (+28%) | yes |
| 4. compute the message digest once, in the broadcaster | 214.2 (+6%) | 80.2 (+8%) | 51.9 (+19%) | yes |
| 5. one process renders a missing cache entry, the others wait | 276.0 (+29%) | 125.5 (+56%) | 74.5 (+44%) | yes |
| 6. cheap local costs: `/play` regex, O(1) message window | 279.9 (+1%) | 134.6 (+7%) | 80.9 (+9%) | yes |
| websocket compression (`compress: true`), client `--deflate 1` | 214.4 (0.77x) | 68.8 (0.51x) | 39.0 (0.48x) | no, see below |
| Zach's batched-writes Bandit fork | 285.8 (1.02x) | 133.8 (0.99x) | 79.2 (0.98x) | no, see below |

(The percentages are against the previous row, except the last two, which are against row 6.) Step 6 was also checked at
a fixed offered load (80 msgs/s, 500 clients): scheduler utilization 50.0% before the regex fix, 46.7% after it, 48.0%
after the window change on top (noise is about 1.5 points), `append_messages` 2.9 to 1.8 us per delivery,
`maybe_play_sound` 1.6 to 0.1 us.

## How it was profiled

`bench/profile-fanout` starts Postgres and the app exactly as `bench/run` does (same seed, pinning, env; the run is
`--prepare-only`'s setup plus a steady load), connects 500 LiveView clients with `bench/loadgen`, posts at a steady rate
below saturation and records three 10 s windows from inside the release with `bin/campfire rpc` (the release has no
`tools` app, so the script copies the local OTP's `tools` ebin into the container for `:tprof`):

1. untraced, the representative one: `:msacc` (where the schedulers spend their time), `:scheduler` wall time,
   reductions by process class, GC counters, and one captured websocket frame;
2. `:tprof` `call_time` on about 40 boundary functions (LiveView channel, diff, render, the serializer, caches,
   Bandit/ThousandIsland, PubSub, Ash): low overhead, so the per-delivery microseconds are close to real;
3. `:tprof` `call_time` on every function of every process, like upstream's eprof: the window slows the VM about 10x, so
   cheap and very frequent functions (a recursion that counts per byte, `List.last`) are inflated. Diagnostic only.

`bench/profile-fanout-analyze DIR` summarises them (`summary.md` in each directory; raw data next to it). A "delivery"
is one viewer handling one posted message: N clients x M messages per window. Directories: `profile-fanout-20261007`
(baseline, 20 msgs/s), `-digest` (after step 4, where the cache herd showed up), `-once` (after step 5, with the full
tprof), `-micro`, `-micro2` (step 6 halves) and `-tuned` (final image, 80 msgs/s).

## Baseline profile (500 clients, 20 msgs/s = 10,000 deliveries/s)

The BEAM used 52% of its 4 schedulers (2.1 cores), 217 us of scheduler time per delivery. Microstate accounting, share of
busy time: emulator 71%, **GC 21%**, port (socket writes) 4%, other 3%. 90.6% of the reductions were in the 500
`RoomLive` processes, 9.1% in the Bandit/ThousandIsland connection processes, the rest nothing. Where one delivery went
(targeted tprof, us; the buckets are exclusive, GC is spread over them, mostly over the LiveView process):

| bucket | us | share |
|---|---:|---:|
| JSON encoding of the diff (Jason, `encode_to_iodata!` in the LiveView channel process) | 57.2 | 28% |
| LiveView diff and render (`Diff.render`: the template tree, the message component, HTML escaping) | 59.4 | 29% |
| websocket framing and socket write (Bandit, ThousandIsland, `port_command`) | 32.9 | 16% |
| handing the frame to the transport process (`Channel.push`: copying a 6 KB iodata) | 18.8 | 9% |
| LiveView callbacks (`handle_info`, stream insert, window) | 11.4 | 6% |
| render cache lookup and hashing (`MessageBody.Cache.fetch`, the md5 of the key) | 8.4 | 4% |
| message component | 5.4 | 3% |
| Ash create and notifiers (per post, divided by viewers) | 7.4 | 4% |
| PubSub dispatch (per post, divided by viewers) | 3.3 | 2% |
| total traced / total measured untraced | 204 / 217 | |

The full tprof agrees with the shape: JSON escaping and encoding (`Jason.Encode.escape_json_chunk/5` alone 22% of all
traced time, 196 million calls: it recurses per chunk of every string), HEEx/Phoenix.HTML escaping and diff traversal
next. Upstream found the same thing for its Cable server (34% decoding, 34% escaping, every connection doing the same
work for the same broadcast), and so did we: **every viewer renders and encodes the identical message**.

Each stream insert is a 6.0 KB frame: LiveView sends the template statics of every keyed stream entry again (3 KB of
`p`), plus the dynamics (the options menu with its 8 quick-boost buttons is most of it). The frame sample is in
`profile-fanout-20261007/frame-sample.json`.

What was not a problem: the per-viewer md5 in the render cache key (0.5 us per delivery, so no change there, only the
digest of the whole message moved to the broadcaster in step 4 for a different reason), per-viewer DB work (none on the
message path), presence (not touched), the sidebar's `{:room_unread}` (a hook that halts for the current room; one
message per delivery, but the harness's single user with N sockets gets N of them per post).

## What changed, and why

1. **`config :phoenix, :json_library, JSON`.** Elixir 1.18+'s built-in encoder produced the same bytes (the bot API's
   `messages_page` body hash is identical to Jason's) and was 1.4x faster on the sample frame in a micro benchmark
   (22.9 vs 32.5 us per encode). Phoenix's websocket frames, the JSON parser, `json/2` and `Phoenix.LiveView.JS` go
   through it; Jason stays a dependency for Ash, Oban and Req. +3% to +6%, and a lot less garbage (peak memory 3.2 to 2.3
   GB). Small, but free and consistent.

2. **`CampfireWeb.SocketSerializer`: encode a diff once.** Phoenix's V2 JSON serializer runs in the LiveView channel
   process, so N viewers do N identical `encode_to_iodata!` calls and send N copies of the iodata to the transport. The
   new serializer (V1 and everything but one case is Phoenix's) keeps the encoded payload of a diff that carries
   templates (a stream insert) in `CampfireWeb.FrameCache`, keyed by the payload term itself (a hit is the same payload,
   never a similar one; no hash to collide), as one binary; only the `[join_ref, ref, topic, "diff", ...]` envelope is
   built per call. 98% hit rate at 500 viewers. JSON encode 57 to 0.4 us and the iodata copy 18.8 to 2.6 us per delivery.
   Same idea as upstream's frame cache. +19% to +65%.

3. **`MessageComponents.cached_message/1`: render a message once.** Every viewer re-rendered the same
   `message/1` (55 us in `Diff.render`). Now the markup is rendered once per message version and viewer class and kept in
   `CampfireWeb.MessageHtmlCache`; the LiveView only looks it up, and the stream insert is one string in the diff instead of
   the template tree. The key: the id, `Message.digest/1`, the mention markup digest, `highlighted`, and what differs
   between viewers: wrote it, is mentioned, is an administrator, and which boosts are theirs. A message the viewer is
   editing or boosting with the custom form is rendered on its own. `Message.digest/1` is the MD5 of the whole message struct
   minus its metadata (attributes, creator, boosts and their boosters), so nothing the render reads can be missed.
   `test/campfire_web/components/cached_message_test.exs` renders `cached_message/1` and `message/1` for author, mentioned,
   administrator and bystander viewers through edits, boosts, renames, highlights, editing/boosting, attachments and sounds
   and compares the HTML. The frame gets 10% bigger (JSON escapes every attribute quote), the server cheaper. +28% to +33%;
   `room_show` (the dead render of 40 messages) gets 21% faster as a side effect.

4. **The digest once, in the broadcaster.** `Campfire.PubSubBroadcaster` puts `Message.digest/1` in the metadata of the
   message it broadcasts (also the message inside a boost event), so the 18 us hash of a message (a 3.8 KB term, measured on the Mac) is done once per post
   instead of once per viewer. Messages from anywhere else compute it on demand. +6% to +19%.

5. **Single flight in `MessageBody.Cache`.** The profile after step 4 showed `Cache.fetch` as the biggest cost, 28 us per
   delivery: 34% of the message-HTML lookups were *misses*. A posted message reaches 500 viewers at the same moment, so everyone misses and
   renders before the first finishes (a thundering herd, because a render is preempted). Now the first caller leaves a
   `{:pending, pid}` marker and renders; the others sleep 1 ms at a time (at most 100) until the value is there; a leader that
   raises removes its marker. One render per entry (tests: 50 concurrent fetches render once). It applies to all three
   caches. +29% to +56%, and the tail latencies shrink with it (1000 clients: p99 73 to 47 ms).

6. **Cheap local costs.** `Campfire.Sound.sound_name/1` ran a regex for every message of every viewer; it now only does for a
   body starting with `/play ` (same result). `RoomLive`'s window of loaded ids is a `:queue` instead of a 300-element list
   that was appended to, trimmed and walked for its last element on every message (`++`, `Enum.take`, `List.last`, 7 us
   in a micro benchmark; `show_welcome?/5` takes the count). +1% to +9%.

Where a delivery goes now (`profile-fanout-20261007-tuned`, 80 msgs/s, 500 clients, 55 us of scheduler time per delivery):
websocket framing and the socket write 7.9 us (of which `port_command` 6.9, the kernel), cache lookups 5.7 (two ETS reads
and the waits), diff and render 6.9, LiveView callbacks 5.8, Ash create 5.1 and PubSub dispatch 3.6 (per post, divided by
500), handing the frame over 2.6, JSON 0.4. GC is 5% of busy time (was 21%). The BEAM is at 2.6 to 2.9 of its 4 cores at
saturation (server CPU per frame: 36 us at 1000 clients).

## Websocket compression (`websocket: [compress: true]`): not adopted

Image with `compress: true` on the `/live` socket, loadgen `--deflate 1` (every socket negotiated permessage-deflate,
`deflate_sockets == clients`), vs the best image without, 2 reps (`results/lv-compress`, `results/lv-best`):

| clients | msgs/s | paced p50 ms | wire MB/s | server cores | CPU us/frame | peak anon MiB |
|---|---|---|---|---|---|---|
| 100 | 279.9 / 214.4 | 18.5 / 22.6 | 185.7 / 4.0 | 2.07 / 2.45 | 74 / 114 | |
| 500 | 134.6 / 68.8 | 26.2 / 33.6 | 446.2 / 6.3 | 2.57 / 3.00 | 38 / 87 | |
| 1000 | 80.9 / 39.0 | 34.0 / 42.6 | 536.5 / 7.2 | 2.89 / 3.32 | 36 / 85 | 2,151 / 2,604 |

(plain / compressed.) The frames shrink 70x (each is the same markup as the last one on that connection, so the
per-connection deflate window predicts it), but the server pays 49 us more per frame (compressing the same bytes once per
connection: the deflate context is per connection, so the frame cache cannot help), throughput halves, and each connection
holds about 0.45 MB of deflate state (+450 MB at 1000). On loopback, where bandwidth is free, that is a plain loss, so it
stays off. For a real deployment the arithmetic is different: at 1 message/s in a 1000-viewer room, plain is 6.6 MB/s
(53 Mbit/s) against about 0.1 MB/s compressed, for 5% of one core and 450 MB; behind a link that cannot carry
the former, turn it on (one word in `endpoint.ex`; browsers negotiate it themselves). The better answer would be Bandit
compressing a frame once for all connections (`server_no_context_takeover`, shared output), which it does not do.

## Bandit's `batched-websocket-writes` fork: no change

`{:bandit, github: "zachdaniel/bandit", branch: "batched-websocket-writes", override: true}` (commit f867519 on 1.12.5), built
from a scratch copy of the tree (the main `mix.exs` and `mix.lock` are untouched), against the best image
(`results/lv-bandit-fork`, `results/lv-best`): 285.8 / 133.8 / 79.2 msgs/s vs 279.9 / 134.6 / 80.9 at 100 / 500 / 1000 clients
(1.02x / 0.99x / 0.98x), same CPU per frame, same p50 and p99 within noise. That is what its code says: it coalesces
the frames a single `WebSock` callback returns as a list (`{:push, [frame, frame], state}`) into one `send`, and Phoenix's
transport pushes one `{:socket_push, ...}` per message, one frame per callback; the frames of a connection arrive 8 ms
apart, so there is nothing to batch. Not adopted, and not worth recommending for this workload unless Phoenix's socket
starts returning lists (draining its mailbox) or a room's traffic per connection becomes bursty.

## Not done

* GC tuning (`min_heap_size`, `fullsweep_after`): GC is 5% of busy time after the changes; not tried.
* Rendering the message before the broadcast (in the broadcaster, to remove the herd's one render and the 1 ms waits,
  about 5 us per delivery): needs a web-layer call from the domain.
* One `LiveComponent` per message (statics are sent once per client): large memory and behaviour cost for a gain
  `cached_message` already takes.
* Stream diffs are still 6.6 KB; a leaner options menu (it is most of the markup) would change the DOM, which these changes do
  not.

## Checks

* `mix precommit`: 502 tests (the baseline's 488 plus the serializer, the cached message, the digest and the single-flight cache).
* Frame equality: `test/campfire_web/socket_serializer_test.exs` (a cached frame equals the stock serializer's, for
  different envelopes).
* The browser (`bench/lib/dom-check.mjs`, headless Chrome through Playwright against the baseline image and the final one,
  outputs in `results/dom-check-20261007`): no console errors, a message posted while the room is open appears with its
  full markup; the options menu opens and a quick boost shows up; the same message after a reload; scrolling up loads the
  older page (40 to 80 messages) and the newest message is still there. After masking ids, timestamps and clock times, the
  DOM of every live, boosted and reloaded message is identical between the baseline image and the tuned one.
* The load generator asserts every posted message reaches every client (`complete == posted`) in all of the above runs.
* Caveats: one user with N sockets is the best case for the caches (one viewer class); with many distinct viewers the render
  is paid once per class of viewer (3 or 4 in practice: the author, the mentioned, administrators, bystanders), still
  independent of the room size. The loader (about 1.1 cores) and the 4 closed-loop posters are not the limit: 16 posters
  gave 83 msgs/s at 1000 clients, 4 gave 81; the server stays at 2.9 of its 4 cores there.
  Single reps vary by about 5%.

## Reproducing

```sh
bench/profile-fanout --image campfire-port:bench --rate 80 --out bench/results/profile-fanout-$(date +%Y%m%d)
bench/profile-fanout-analyze bench/results/profile-fanout-... > bench/results/profile-fanout-.../summary.md
SUITES=liveview bench/run --apps campfire=campfire-port:IMAGE --reps 2 --out bench/results/lv-NAME
bench/lvsum bench/results/lv-baseline-rerun bench/results/lv-NAME               # fan-out only, side by side
LIVEVIEW_ARGS="--deflate 1" SUITES=liveview bench/run --apps campfire=campfire-port:compress --reps 2 --out ...
```

Images (`docker build -t campfire-port:NAME .` at each step) are not kept in the repository; the steps are the sections
above, in order.
