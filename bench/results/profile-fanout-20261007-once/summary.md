# Fan-out profile: profile-fanout-20261007-once

`run.json`: {  "clients": 500,  "rate": 80.0,  "secs": 10,  "image": "campfire-port:once",  "cpu": {   "untraced": {    "app_cpu_s": 23.542162,    "db_cpu_s": 0.880427   },   "targeted": {    "app_cpu_s": 17.568815,    "db_cpu_s": 0.637015   },   "tprof": {    "app_cpu_s": 178.382514,    "db_cpu_s": 4.243112   }  } }

## Untraced window

```
%{
  memory: [
    total: 1091217856,
    processes: 906764512,
    processes_used: 906198304,
    system: 184453344,
    atom: 2622337,
    atom_used: 2622337,
    binary: 44349592,
    code: 80253487,
    ets: 9395888
  ],
  processes: 1591,
  reductions: 724366979,
  schedulers_online: 4,
  json_library: JSON,
  window_secs: 10,
  gcs: 147883,
  gc_words_reclaimed: 1283590564,
  io_input_bytes: 1323546,
  io_output_bytes: 2449616231
}
```

Scheduler wall time (`:scheduler.utilization`): weighted 50.0% of the online schedulers (total over all 30 incl. offline: 10.0%); busy normal schedulers 1:52% 2:50% 3:48% 4:50%

Microstate accounting, normal schedulers that ran (10), share of wall time and of busy time:

| state | % of wall | % of busy |
|---|---:|---:|
| sleep | 77.7% | - |
| emulator | 13.4% | 60.2% |
| other | 4.2% | 18.7% |
| port | 2.1% | 9.3% |
| gc | 1.7% | 7.8% |
| check_io | 0.5% | 2.3% |
| aux | 0.4% | 1.6% |

Reductions by process class (top):

```
other (CampfireWeb.RoomLive)                                      500 procs      494284884 reductions 68.2%
Bandit/ThousandIsland connection (websocket transport)            501 procs      224725585 reductions 31.0%
other (:erpc)                                                       1 procs        4728691 reductions 0.7%
other (DBConnection.ConnectionPool)                                 1 procs         241317 reductions 0.0%
other (:user_drv)                                                   1 procs         103994 reductions 0.0%
other (:group)                                                      1 procs         101686 reductions 0.0%
```

## Targeted tprof (call_time on boundary functions)

`deliveries` = LiveView renders in the window = 363000. us/delivery = time of the function / deliveries (the per-viewer cost of one posted message).

| function | calls | total ms | us/call | us/delivery |
|---|---:|---:|---:|---:|
| `ThousandIsland.Socket.send/2` | 364225 | 2529 | 6.9 | 7.0 |
| `Phoenix.LiveView.Diff.render/4` | 363000 | 1923 | 5.3 | 5.3 |
| `CampfireWeb.MessageBody.Cache.fetch/3` | 726726 | 1910 | 2.6 | 5.3 |
| `Ash.create/3` | 726 | 1545 | 2129.0 | 4.3 |
| `Registry.dispatch/4` | 2905 | 1274 | 438.9 | 3.5 |
| `CampfireWeb.RoomLive.append_messages/2` | 363000 | 1058 | 2.9 | 2.9 |
| `Phoenix.LiveView.Channel.push/3` | 363000 | 917 | 2.5 | 2.5 |
| `CampfireWeb.RoomLive.maybe_play_sound/2` | 363000 | 569 | 1.6 | 1.6 |
| `Phoenix.LiveView.Channel.handle_info/2` | 725993 | 495 | 0.7 | 1.4 |
| `CampfireWeb.RoomLive.handle_info/2` | 363000 | 455 | 1.3 | 1.3 |
| `Campfire.Notifiers.Fanout.notify/1` | 726 | 417 | 575.1 | 1.2 |
| `Phoenix.LiveView.Channel.render_diff/3` | 725993 | 403 | 0.6 | 1.1 |
| `Bandit.WebSocket.Connection.handle_info/3` | 363000 | 188 | 0.5 | 0.5 |
| `Phoenix.LiveView.Lifecycle.after_render/1` | 363000 | 185 | 0.5 | 0.5 |
| `CampfireWeb.RoomLive.decorate/2` | 363000 | 145 | 0.4 | 0.4 |
| `CampfireWeb.MessageBody.digest/2` | 363726 | 142 | 0.4 | 0.4 |
| `Phoenix.LiveView.Renderer.to_rendered/2` | 363000 | 129 | 0.4 | 0.4 |
| `JSON.encode_to_iodata!/2` | 364952 | 115 | 0.3 | 0.3 |
| `Phoenix.LiveView.Diff.render_private/2` | 725993 | 106 | 0.1 | 0.3 |
| `CampfireWeb.RoomLive.render/1` | 363000 | 100 | 0.3 | 0.3 |
| `CampfireWeb.BotMessageController.create/2` | 726 | 80 | 110.9 | 0.2 |
| `Campfire.Chat.create_message/3` | 726 | 77 | 106.4 | 0.2 |
| `Bandit.WebSocket.Frame.serialize/1` | 363500 | 70 | 0.2 | 0.2 |
| `Bandit.WebSocket.Handler.handle_info/2` | 363000 | 63 | 0.2 | 0.2 |
| `Phoenix.LiveView.Utils.clear_changed/1` | 363000 | 53 | 0.1 | 0.1 |
| `CampfireWeb.RoomLive.stop_typing/2` | 363000 | 48 | 0.1 | 0.1 |
| `Phoenix.Socket.__info__/2` | 363000 | 40 | 0.1 | 0.1 |
| `JSON.encode_to_iodata!/1` | 364952 | 36 | 0.1 | 0.1 |

### Where one delivery goes (targeted tprof, us per delivery; tracing only ~40 functions, so close to real)

| bucket | us/delivery | share of traced |
|---|---:|---:|
| JSON encoding (serializer) | 0.4 | 1.0% |
| LiveView diff and render (Diff.render, RoomLive.render) | 8.0 | 19.4% |
| message component render (MessageComponents, emoji_only?) | 0.0 | 0.1% |
| render cache lookup and hashing (Cache.fetch, digest) | 5.7 | 13.8% |
| hand the frame to the transport (Channel.push: send/copy) | 2.5 | 6.1% |
| websocket framing and socket write (Bandit, ThousandIsland) | 8.0 | 19.4% |
| LiveView callbacks (handle_info, stream insert, window, sound) | 7.6 | 18.6% |
| PubSub dispatch (Registry.dispatch, per post / viewers) | 3.5 | 8.5% |
| Ash create + notifiers (per post / viewers) | 5.4 | 13.1% |
| traced total | 41.1 | |
| **all threads busy, untraced window (incl. GC, port, scheduling, the poster's Ash/PubSub work)** | 57.7 | (80 msgs/s x 500 clients x 10 s = 400000 deliveries) |

## Full tprof (every function; tracing inflates cheap, frequent functions)

Total traced time 23373 ms.

| bucket | time ms | share |
|---|---:|---:|
| other (Enum/Map/:lists/:erlang BIFs, GenServer, ...) | 10029 | 42.9% |
| HEEx runtime: LiveView diff, engine, Phoenix.HTML escaping | 5408 | 23.1% |
| websocket framing and writes (Bandit / ThousandIsland / port) | 2066 | 8.8% |
| Ash / Ecto / DB / notifiers | 2017 | 8.6% |
| render cache lookup / hashing | 1383 | 5.9% |
| RoomLive callbacks (Campfire web, other) | 1243 | 5.3% |
| message component and body render (Campfire web) | 654 | 2.8% |
| JSON encoding (Jason / JSON / serializer) | 542 | 2.3% |
| PubSub dispatch (Phoenix.PubSub, Registry) | 28 | 0.1% |

Top functions:

| function | calls | ms | share |
|---|---:|---:|---:|
| `:erts_internal.port_command/3` | 166038 | 1173 | 5.0% |
| `List.last/2` | 24075966 | 985 | 4.2% |
| `:ets.lookup_element/4` | 1069829 | 847 | 3.6% |
| `:erlang.send/2` | 485688 | 709 | 3.0% |
| `Enum.-reduce/3-lists^foldl/2-0-/3` | 4841377 | 448 | 1.9% |
| `:gen_server.loop/5` | 489307 | 429 | 1.8% |
| `Phoenix.LiveView.Diff.traverse_dynamic/8` | 5136000 | 399 | 1.7% |
| `Phoenix.LiveView.Engine.changed_assign?/2` | 5473050 | 290 | 1.2% |
| `Enum.-map/2-lists^map/1-1-/2` | 2262772 | 250 | 1.1% |
| `Enum.predicate_list/3` | 2773933 | 243 | 1.0% |
| `:re.import/1` | 173346 | 233 | 1.0% |
| `:erlang.++/2` | 756335 | 222 | 1.0% |
| `Phoenix.LiveView.Engine.nested_changed_assign?/4` | 2095167 | 210 | 0.9% |
| `Phoenix.LiveView.Utils.force_assign/4` | 1126389 | 210 | 0.9% |
| `:maps.put/3` | 2234811 | 210 | 0.9% |
| `Plug.HTML.to_iodata/5` | 4519038 | 202 | 0.9% |
| `:gen_server.decode_msg/4` | 488985 | 189 | 0.8% |
| `:lists.member/2` | 762464 | 183 | 0.8% |
| `Map.get/3` | 2915532 | 179 | 0.8% |
| `Phoenix.LiveView.Diff.traverse/6` | 1123500 | 178 | 0.8% |
| `:lists.keyfind/3` | 2556128 | 149 | 0.6% |
| `CampfireWeb.MessageBody.Cache.lookup_or_render/4` | 487319 | 146 | 0.6% |
| `:erlang.function_exported/3` | 620800 | 145 | 0.6% |
| `CampfireWeb.RoomLive.-render/1-fun-3-/3` | 160500 | 144 | 0.6% |
| `Access.get/3` | 2364154 | 142 | 0.6% |

