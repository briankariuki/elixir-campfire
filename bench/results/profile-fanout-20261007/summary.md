# Fan-out profile: profile-fanout-20261007

`run.json`: {  "clients": 500,  "rate": 20,  "secs": 10,  "image": "campfire-port:baseline",  "cpu": {   "targeted": {    "app_cpu_s": 19.085364,    "db_cpu_s": 0.175652   }  } }

## Untraced window

```
%{
  memory: [
    total: 730497324,
    processes: 575434888,
    processes_used: 575059480,
    system: 155062436,
    atom: 2621979,
    atom_used: 2621979,
    binary: 18187304,
    code: 80238579,
    ets: 7176360
  ],
  processes: 1589,
  reductions: 1513245142,
  schedulers_online: 4,
  json_library: Jason,
  window_secs: 10,
  gcs: 308013,
  gc_words_reclaimed: 2196176285,
  io_input_bytes: 336182,
  io_output_bytes: 563769370
}
```

Scheduler wall time (`:scheduler.utilization`): weighted 52.2% of the online schedulers (total over all 30 incl. offline: 10.4%); busy normal schedulers 1:54% 2:50% 3:55% 4:50%

Microstate accounting, normal schedulers that ran (10), share of wall time and of busy time:

| state | % of wall | % of busy |
|---|---:|---:|
| sleep | 78.8% | - |
| emulator | 15.1% | 71.0% |
| gc | 4.4% | 20.6% |
| port | 0.8% | 3.8% |
| other | 0.6% | 3.0% |
| aux | 0.2% | 0.9% |
| check_io | 0.2% | 0.8% |

Reductions by process class (top):

```
other (CampfireWeb.RoomLive)                                      500 procs     1370682009 reductions 90.6%
Bandit/ThousandIsland connection (websocket transport)            501 procs      137300483 reductions 9.1%
other (:erpc)                                                       1 procs        4779478 reductions 0.3%
other (CampfireWeb.MessageBody.Cache)                               1 procs         253054 reductions 0.0%
other (DBConnection.ConnectionPool)                                 1 procs          61441 reductions 0.0%
other (:erts_trace_cleaner)                                         1 procs          58990 reductions 0.0%
```

## Targeted tprof (call_time on boundary functions)

`deliveries` = LiveView renders in the window = 92000. us/delivery = time of the function / deliveries (the per-viewer cost of one posted message).

| function | calls | total ms | us/call | us/delivery |
|---|---:|---:|---:|---:|
| `Jason.encode_to_iodata!/2` | 92194 | 5206 | 56.5 | 56.6 |
| `Phoenix.LiveView.Diff.render/4` | 92000 | 5102 | 55.5 | 55.5 |
| `ThousandIsland.Socket.send/2` | 91749 | 1870 | 20.4 | 20.3 |
| `Phoenix.LiveView.Channel.push/3` | 92000 | 1730 | 18.8 | 18.8 |
| `CampfireWeb.MessageBody.Cache.fetch/3` | 92000 | 696 | 7.6 | 7.6 |
| `Bandit.WebSocket.Frame.serialize/1` | 91566 | 575 | 6.3 | 6.3 |
| `Bandit.WebSocket.Connection.handle_info/3` | 91566 | 545 | 6.0 | 5.9 |
| `Ash.create/3` | 184 | 509 | 2769.0 | 5.5 |
| `CampfireWeb.RoomLive.append_messages/2` | 92000 | 403 | 4.4 | 4.4 |
| `Registry.dispatch/4` | 736 | 300 | 408.1 | 3.3 |
| `CampfireWeb.MessageComponents.message/1` | 92000 | 247 | 2.7 | 2.7 |
| `CampfireWeb.RoomLive.maybe_play_sound/2` | 92000 | 197 | 2.1 | 2.1 |
| `CampfireWeb.MessageBody.emoji_only?/1` | 92000 | 176 | 1.9 | 1.9 |
| `Campfire.Notifiers.Fanout.notify/1` | 184 | 169 | 922.6 | 1.8 |
| `Phoenix.LiveView.Channel.handle_info/2` | 183516 | 166 | 0.9 | 1.8 |
| `CampfireWeb.RoomLive.handle_info/2` | 92000 | 158 | 1.7 | 1.7 |
| `Phoenix.LiveView.Channel.render_diff/3` | 183516 | 141 | 0.8 | 1.5 |
| `CampfireWeb.RoomLive.decorate/2` | 92000 | 94 | 1.0 | 1.0 |
| `Phoenix.LiveView.Lifecycle.after_render/1` | 92000 | 78 | 0.9 | 0.9 |
| `Phoenix.Socket.V2.JSONSerializer.encode!/1` | 92000 | 44 | 0.5 | 0.5 |
| `CampfireWeb.MessageBody.digest/2` | 92000 | 44 | 0.5 | 0.5 |
| `Phoenix.LiveView.Renderer.to_rendered/2` | 92000 | 43 | 0.5 | 0.5 |
| `Phoenix.LiveView.Diff.render_private/2` | 183516 | 35 | 0.2 | 0.4 |
| `CampfireWeb.MessageBody.cached_html/3` | 92000 | 33 | 0.4 | 0.4 |
| `CampfireWeb.RoomLive.render/1` | 92000 | 31 | 0.3 | 0.3 |
| `CampfireWeb.MessageComponents.actions/1` | 92000 | 30 | 0.3 | 0.3 |
| `Phoenix.LiveView.Utils.clear_changed/1` | 92000 | 28 | 0.3 | 0.3 |
| `CampfireWeb.RoomLive.stop_typing/2` | 92000 | 26 | 0.3 | 0.3 |
| `CampfireWeb.BotMessageController.create/2` | 184 | 23 | 130.2 | 0.3 |
| `Campfire.Chat.create_message/3` | 184 | 23 | 128.6 | 0.3 |
| `Bandit.WebSocket.Handler.handle_info/2` | 91566 | 21 | 0.2 | 0.2 |

### Where one delivery goes (targeted tprof, us per delivery; tracing only ~40 functions, so close to real)

| bucket | us/delivery | share of traced |
|---|---:|---:|
| JSON encoding (serializer) | 57.2 | 28.0% |
| LiveView diff and render (Diff.render, RoomLive.render) | 59.4 | 29.1% |
| message component render (MessageComponents, emoji_only?) | 5.4 | 2.6% |
| render cache lookup and hashing (Cache.fetch, digest) | 8.4 | 4.1% |
| hand the frame to the transport (Channel.push: send/copy) | 18.8 | 9.2% |
| websocket framing and socket write (Bandit, ThousandIsland) | 32.9 | 16.1% |
| LiveView callbacks (handle_info, stream insert, window, sound) | 11.4 | 5.6% |
| PubSub dispatch (Registry.dispatch, per post / viewers) | 3.3 | 1.6% |
| Ash create + notifiers (per post / viewers) | 7.4 | 3.6% |
| traced total | 204.1 | |
| **all threads busy, untraced window (incl. GC, port, scheduling, the poster's Ash/PubSub work)** | 217.2 | (20 msgs/s x 500 clients x 10 s = 100000 deliveries) |

## Full tprof (every function; tracing inflates cheap, frequent functions)

Total traced time 35435 ms.

| bucket | time ms | share |
|---|---:|---:|
| JSON encoding (Jason / JSON / serializer) | 13331 | 37.6% |
| other (Enum/Map/:lists/:erlang BIFs, GenServer, ...) | 11648 | 32.9% |
| HEEx runtime: LiveView diff, engine, Phoenix.HTML escaping | 6847 | 19.3% |
| websocket framing and writes (Bandit / ThousandIsland / port) | 1267 | 3.6% |
| message component and body render (Campfire web) | 873 | 2.5% |
| Ash / Ecto / DB / notifiers | 644 | 1.8% |
| RoomLive callbacks (Campfire web, other) | 519 | 1.5% |
| render cache lookup / hashing | 296 | 0.8% |
| PubSub dispatch (Phoenix.PubSub, Registry) | 7 | 0.0% |

Top functions:

| function | calls | ms | share |
|---|---:|---:|---:|
| `Jason.Encode.escape_json_chunk/5` | 196711852 | 7826 | 22.1% |
| `Phoenix.HTML.Engine.html_escape/5` | 35747374 | 1434 | 4.0% |
| `:erlang.integer_to_binary/1` | 7549979 | 1325 | 3.7% |
| `Jason.Encode.escape_json/4` | 26580688 | 1272 | 3.6% |
| `:erts_internal.port_command/3` | 46507 | 983 | 2.8% |
| `:erlang.iolist_to_binary/1` | 2268401 | 928 | 2.6% |
| `:erlang.send/2` | 141065 | 917 | 2.6% |
| `Jason.Encode.map_naive_loop/3` | 6657301 | 799 | 2.3% |
| `Phoenix.LiveView.Diff.traverse_dynamic/8` | 6114315 | 578 | 1.6% |
| `Jason.Encode.escape/1` | 13223360 | 577 | 1.6% |
| `Jason.Encode.value/3` | 10767123 | 549 | 1.5% |
| `:erlang.iolist_size/1` | 94981 | 523 | 1.5% |
| `Jason.Encode.encode_string/2` | 6701220 | 479 | 1.4% |
| `Jason.Encode.escape_json/1` | 13357328 | 477 | 1.3% |
| `Jason.Encode.key/2` | 6656156 | 451 | 1.3% |
| `String.Chars.to_string/1` | 5454612 | 429 | 1.2% |
| `Enum.-map/2-lists^map/1-1-/2` | 4719750 | 416 | 1.2% |
| `String.Chars.Integer.to_string/1` | 5448841 | 411 | 1.2% |
| `String.Chars.impl_for!/1` | 5454611 | 387 | 1.1% |
| `Jason.Encode.list_loop/3` | 3976656 | 363 | 1.0% |
| `Phoenix.HTML.build_attrs/1` | 3614159 | 349 | 1.0% |
| `Phoenix.LiveView.Diff.traverse/6` | 2811385 | 340 | 1.0% |
| `:maps.put/3` | 2450414 | 323 | 0.9% |
| `List.last/2` | 6691917 | 285 | 0.8% |
| `:gen_server.decode_msg/4` | 142543 | 252 | 0.7% |

