# Fan-out profile: profile-fanout-20261007-tuned

`run.json`: {  "clients": 500,  "rate": 80.0,  "secs": 10,  "image": "campfire-port:bench",  "cpu": {   "untraced": {    "app_cpu_s": 22.05372,    "db_cpu_s": 0.852458   },   "targeted": {    "app_cpu_s": 16.449877,    "db_cpu_s": 0.635288   },   "tprof": {    "app_cpu_s": 167.800829,    "db_cpu_s": 4.131805   }  } }

## Untraced window

```
%{
  memory: [
    total: 1087433644,
    processes: 901896528,
    processes_used: 901351200,
    system: 185537116,
    atom: 2622361,
    atom_used: 2622361,
    binary: 46354512,
    code: 80254003,
    ets: 9402504
  ],
  processes: 1591,
  reductions: 655727803,
  schedulers_online: 4,
  json_library: JSON,
  window_secs: 10,
  gcs: 123182,
  gc_words_reclaimed: 1068904666,
  io_input_bytes: 1336248,
  io_output_bytes: 2476282506
}
```

Scheduler wall time (`:scheduler.utilization`): weighted 47.3% of the online schedulers (total over all 30 incl. offline: 9.5%); busy normal schedulers 1:49% 2:47% 3:46% 4:47%

Microstate accounting, normal schedulers that ran (10), share of wall time and of busy time:

| state | % of wall | % of busy |
|---|---:|---:|
| sleep | 78.9% | - |
| emulator | 12.8% | 60.8% |
| other | 4.3% | 20.3% |
| port | 2.1% | 9.8% |
| gc | 1.1% | 5.4% |
| check_io | 0.5% | 2.4% |
| aux | 0.3% | 1.4% |

Reductions by process class (top):

```
other (CampfireWeb.RoomLive)                                      500 procs      423350851 reductions 64.5%
Bandit/ThousandIsland connection (websocket transport)            501 procs      227251223 reductions 34.6%
other (:erpc)                                                       1 procs        4728759 reductions 0.7%
other (DBConnection.ConnectionPool)                                 1 procs         244513 reductions 0.0%
other (:user_drv)                                                   1 procs         105152 reductions 0.0%
other (:group)                                                      1 procs         101697 reductions 0.0%
```

## Targeted tprof (call_time on boundary functions)

`deliveries` = LiveView renders in the window = 368998. us/delivery = time of the function / deliveries (the per-viewer cost of one posted message).

| function | calls | total ms | us/call | us/delivery |
|---|---:|---:|---:|---:|
| `ThousandIsland.Socket.send/2` | 369787 | 2560 | 6.9 | 6.9 |
| `CampfireWeb.MessageBody.Cache.fetch/3` | 738396 | 1950 | 2.6 | 5.3 |
| `Ash.create/3` | 737 | 1503 | 2040.3 | 4.1 |
| `Phoenix.LiveView.Diff.render/4` | 368998 | 1402 | 3.8 | 3.8 |
| `Registry.dispatch/4` | 2950 | 1326 | 449.7 | 3.6 |
| `Phoenix.LiveView.Channel.push/3` | 368660 | 958 | 2.6 | 2.6 |
| `CampfireWeb.RoomLive.handle_info/2` | 368998 | 673 | 1.8 | 1.8 |
| `CampfireWeb.RoomLive.append_messages/2` | 368998 | 618 | 1.7 | 1.7 |
| `Phoenix.LiveView.Channel.render_diff/3` | 737498 | 570 | 0.8 | 1.5 |
| `Phoenix.LiveView.Channel.handle_info/2` | 737498 | 462 | 0.6 | 1.3 |
| `Campfire.Notifiers.Fanout.notify/1` | 738 | 364 | 494.5 | 1.0 |
| `CampfireWeb.RoomLive.decorate/2` | 368998 | 267 | 0.7 | 0.7 |
| `Phoenix.LiveView.Lifecycle.after_render/1` | 368660 | 203 | 0.6 | 0.6 |
| `Bandit.WebSocket.Connection.handle_info/3` | 368550 | 183 | 0.5 | 0.5 |
| `CampfireWeb.MessageBody.digest/2` | 369736 | 145 | 0.4 | 0.4 |
| `Phoenix.LiveView.Renderer.to_rendered/2` | 368998 | 115 | 0.3 | 0.3 |
| `JSON.encode_to_iodata!/2` | 370629 | 111 | 0.3 | 0.3 |
| `Phoenix.LiveView.Diff.render_private/2` | 737160 | 103 | 0.1 | 0.3 |
| `CampfireWeb.RoomLive.render/1` | 368998 | 94 | 0.3 | 0.3 |
| `CampfireWeb.BotMessageController.create/2` | 737 | 77 | 104.7 | 0.2 |
| `Campfire.Chat.create_message/3` | 737 | 73 | 99.2 | 0.2 |
| `Bandit.WebSocket.Handler.handle_info/2` | 368550 | 71 | 0.2 | 0.2 |
| `Bandit.WebSocket.Frame.serialize/1` | 369050 | 69 | 0.2 | 0.2 |
| `Phoenix.LiveView.Utils.clear_changed/1` | 368660 | 59 | 0.2 | 0.2 |
| `CampfireWeb.RoomLive.stop_typing/2` | 368998 | 58 | 0.2 | 0.2 |
| `CampfireWeb.RoomLive.maybe_play_sound/2` | 368998 | 47 | 0.1 | 0.1 |
| `JSON.encode_to_iodata!/1` | 370629 | 44 | 0.1 | 0.1 |
| `Phoenix.Socket.__info__/2` | 368550 | 40 | 0.1 | 0.1 |

### Where one delivery goes (targeted tprof, us per delivery; tracing only ~40 functions, so close to real)

| bucket | us/delivery | share of traced |
|---|---:|---:|
| JSON encoding (serializer) | 0.4 | 1.1% |
| LiveView diff and render (Diff.render, RoomLive.render) | 6.9 | 18.2% |
| message component render (MessageComponents, emoji_only?) | 0.0 | 0.1% |
| render cache lookup and hashing (Cache.fetch, digest) | 5.7 | 15.0% |
| hand the frame to the transport (Channel.push: send/copy) | 2.6 | 6.8% |
| websocket framing and socket write (Bandit, ThousandIsland) | 7.9 | 20.9% |
| LiveView callbacks (handle_info, stream insert, window, sound) | 5.8 | 15.2% |
| PubSub dispatch (Registry.dispatch, per post / viewers) | 3.6 | 9.5% |
| Ash create + notifiers (per post / viewers) | 5.1 | 13.3% |
| traced total | 38.0 | |
| **all threads busy, untraced window (incl. GC, port, scheduling, the poster's Ash/PubSub work)** | 54.6 | (80 msgs/s x 500 clients x 10 s = 400000 deliveries) |

## Full tprof (every function; tracing inflates cheap, frequent functions)

Total traced time 22619 ms.

| bucket | time ms | share |
|---|---:|---:|
| other (Enum/Map/:lists/:erlang BIFs, GenServer, ...) | 8990 | 39.7% |
| HEEx runtime: LiveView diff, engine, Phoenix.HTML escaping | 5753 | 25.4% |
| websocket framing and writes (Bandit / ThousandIsland / port) | 2184 | 9.7% |
| Ash / Ecto / DB / notifiers | 2138 | 9.5% |
| RoomLive callbacks (Campfire web, other) | 1184 | 5.2% |
| render cache lookup / hashing | 1166 | 5.2% |
| message component and body render (Campfire web) | 621 | 2.7% |
| JSON encoding (Jason / JSON / serializer) | 546 | 2.4% |
| PubSub dispatch (Phoenix.PubSub, Registry) | 32 | 0.1% |

Top functions:

| function | calls | ms | share |
|---|---:|---:|---:|
| `:erts_internal.port_command/3` | 174807 | 1272 | 5.6% |
| `:erlang.send/2` | 510905 | 754 | 3.3% |
| `:ets.lookup_element/4` | 1089758 | 668 | 3.0% |
| `Enum.-reduce/3-lists^foldl/2-0-/3` | 5421569 | 459 | 2.0% |
| `Phoenix.LiveView.Diff.traverse_dynamic/8` | 5397220 | 428 | 1.9% |
| `:gen_server.loop/5` | 515201 | 412 | 1.8% |
| `:lists.member/2` | 968758 | 358 | 1.6% |
| `Phoenix.LiveView.Engine.changed_assign?/2` | 5746683 | 336 | 1.5% |
| `Enum.predicate_list/3` | 2912336 | 247 | 1.1% |
| `:maps.put/3` | 2350288 | 233 | 1.0% |
| `Plug.HTML.to_iodata/5` | 4744566 | 231 | 1.0% |
| `Phoenix.LiveView.Utils.force_assign/4` | 1183584 | 229 | 1.0% |
| `Enum.-map/2-lists^map/1-1-/2` | 2039339 | 213 | 0.9% |
| `Phoenix.LiveView.Diff.traverse/6` | 1180060 | 211 | 0.9% |
| `Phoenix.LiveView.Engine.nested_changed_assign?/4` | 2199730 | 201 | 0.9% |
| `Map.get/3` | 3062435 | 197 | 0.9% |
| `:queue.len/1` | 337020 | 184 | 0.8% |
| `Enum.reduce/3` | 1997065 | 150 | 0.7% |
| `Access.get/3` | 2483493 | 149 | 0.7% |
| `Map.get/2` | 2499979 | 147 | 0.7% |
| `Map.update!/3` | 1248392 | 146 | 0.6% |
| `:lists.keyfind/3` | 2176797 | 146 | 0.6% |
| `CampfireWeb.RoomLive.-render/1-fun-3-/3` | 168510 | 144 | 0.6% |
| `:gen_server.decode_msg/4` | 514370 | 142 | 0.6% |
| `:ets.lookup/2` | 592877 | 141 | 0.6% |

