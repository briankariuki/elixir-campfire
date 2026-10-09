# Fan-out profile: profile-fanout-20261007-digest

`run.json`: {  "clients": 500,  "rate": 40.0,  "secs": 10,  "image": "campfire-port:digest",  "cpu": {   "untraced": {    "app_cpu_s": 18.206743,    "db_cpu_s": 0.469943   },   "targeted": {    "app_cpu_s": 13.032059,    "db_cpu_s": 0.344534   },   "tprof": {    "app_cpu_s": 131.393606,    "db_cpu_s": 1.611177   }  } }

## Untraced window

```
%{
  memory: [
    total: 1020770956,
    processes: 842050656,
    processes_used: 841548104,
    system: 178720300,
    atom: 2622307,
    atom_used: 2622307,
    binary: 37214056,
    code: 80251539,
    ets: 8529952
  ],
  processes: 1591,
  reductions: 633948927,
  schedulers_online: 4,
  json_library: JSON,
  window_secs: 10,
  gcs: 129502,
  gc_words_reclaimed: 888284511,
  io_input_bytes: 637101,
  io_output_bytes: 1176371264
}
```

Scheduler wall time (`:scheduler.utilization`): weighted 38.3% of the online schedulers (total over all 30 incl. offline: 7.7%); busy normal schedulers 1:38% 2:38% 3:40% 4:38%

Microstate accounting, normal schedulers that ran (10), share of wall time and of busy time:

| state | % of wall | % of busy |
|---|---:|---:|
| sleep | 83.6% | - |
| emulator | 11.0% | 67.3% |
| gc | 2.0% | 12.2% |
| other | 1.7% | 10.4% |
| port | 1.0% | 6.4% |
| aux | 0.3% | 1.9% |
| check_io | 0.3% | 1.7% |

Reductions by process class (top):

```
other (CampfireWeb.RoomLive)                                      500 procs      520436664 reductions 82.0%
Bandit/ThousandIsland connection (websocket transport)            501 procs      108003813 reductions 17.0%
other (:erpc)                                                       1 procs        4727757 reductions 0.7%
other (CampfireWeb.MessageBody.Cache)                               3 procs        1248686 reductions 0.2%
other (DBConnection.ConnectionPool)                                 1 procs         116657 reductions 0.0%
other (:erts_trace_cleaner)                                         1 procs          57251 reductions 0.0%
```

## Targeted tprof (call_time on boundary functions)

`deliveries` = LiveView renders in the window = 177500. us/delivery = time of the function / deliveries (the per-viewer cost of one posted message).

| function | calls | total ms | us/call | us/delivery |
|---|---:|---:|---:|---:|
| `CampfireWeb.MessageBody.Cache.fetch/3` | 416210 | 5036 | 12.1 | 28.4 |
| `ThousandIsland.Socket.send/2` | 178355 | 1262 | 7.1 | 7.1 |
| `Ash.create/3` | 356 | 906 | 2545.3 | 5.1 |
| `CampfireWeb.RoomLive.append_messages/2` | 177500 | 881 | 5.0 | 5.0 |
| `Phoenix.LiveView.Diff.render/4` | 177500 | 849 | 4.8 | 4.8 |
| `Registry.dispatch/4` | 1421 | 687 | 483.8 | 3.9 |
| `Phoenix.LiveView.Channel.push/3` | 177500 | 477 | 2.7 | 2.7 |
| `CampfireWeb.RoomLive.maybe_play_sound/2` | 177500 | 322 | 1.8 | 1.8 |
| `Phoenix.LiveView.Channel.render_diff/3` | 355000 | 322 | 0.9 | 1.8 |
| `CampfireWeb.RoomLive.handle_info/2` | 177500 | 295 | 1.7 | 1.7 |
| `Phoenix.LiveView.Channel.handle_info/2` | 355000 | 253 | 0.7 | 1.4 |
| `Campfire.Notifiers.Fanout.notify/1` | 355 | 227 | 641.7 | 1.3 |
| `CampfireWeb.MessageComponents.message/1` | 61210 | 195 | 3.2 | 1.1 |
| `CampfireWeb.RoomLive.decorate/2` | 177500 | 178 | 1.0 | 1.0 |
| `JSON.encode_to_iodata!/2` | 180760 | 127 | 0.7 | 0.7 |
| `CampfireWeb.MessageBody.emoji_only?/1` | 61210 | 123 | 2.0 | 0.7 |
| `Phoenix.LiveView.Lifecycle.after_render/1` | 177500 | 117 | 0.7 | 0.7 |
| `CampfireWeb.MessageBody.digest/2` | 238710 | 117 | 0.5 | 0.7 |
| `Phoenix.LiveView.Renderer.to_rendered/2` | 177500 | 98 | 0.6 | 0.6 |
| `Bandit.WebSocket.Connection.handle_info/3` | 177500 | 94 | 0.5 | 0.5 |
| `CampfireWeb.MessageBody.cached_html/3` | 61210 | 86 | 1.4 | 0.5 |
| `CampfireWeb.RoomLive.render/1` | 177500 | 58 | 0.3 | 0.3 |
| `CampfireWeb.RoomLive.stop_typing/2` | 177500 | 53 | 0.3 | 0.3 |
| `Phoenix.LiveView.Diff.render_private/2` | 355000 | 52 | 0.1 | 0.3 |
| `Phoenix.LiveView.Utils.clear_changed/1` | 177500 | 45 | 0.3 | 0.3 |
| `Campfire.Chat.create_message/3` | 356 | 40 | 113.8 | 0.2 |
| `CampfireWeb.BotMessageController.create/2` | 356 | 40 | 113.0 | 0.2 |
| `Bandit.WebSocket.Handler.handle_info/2` | 177500 | 39 | 0.2 | 0.2 |
| `Bandit.WebSocket.Frame.serialize/1` | 178000 | 33 | 0.2 | 0.2 |
| `CampfireWeb.MessageComponents.actions/1` | 61210 | 26 | 0.4 | 0.2 |
| `CampfireWeb.MessageComponents.boosts/1` | 61210 | 26 | 0.4 | 0.1 |
| `JSON.encode_to_iodata!/1` | 180760 | 22 | 0.1 | 0.1 |

### Where one delivery goes (targeted tprof, us per delivery; tracing only ~40 functions, so close to real)

| bucket | us/delivery | share of traced |
|---|---:|---:|
| JSON encoding (serializer) | 0.8 | 1.1% |
| LiveView diff and render (Diff.render, RoomLive.render) | 8.7 | 11.8% |
| message component render (MessageComponents, emoji_only?) | 2.2 | 3.0% |
| render cache lookup and hashing (Cache.fetch, digest) | 29.5 | 40.1% |
| hand the frame to the transport (Channel.push: send/copy) | 2.7 | 3.7% |
| websocket framing and socket write (Bandit, ThousandIsland) | 8.2 | 11.1% |
| LiveView callbacks (handle_info, stream insert, window, sound) | 11.2 | 15.2% |
| PubSub dispatch (Registry.dispatch, per post / viewers) | 3.9 | 5.3% |
| Ash create + notifiers (per post / viewers) | 6.4 | 8.7% |
| traced total | 73.5 | |
| **all threads busy, untraced window (incl. GC, port, scheduling, the poster's Ash/PubSub work)** | 83.8 | (40 msgs/s x 500 clients x 10 s = 200000 deliveries) |

## Full tprof (every function; tracing inflates cheap, frequent functions)

Total traced time 29555 ms.

| bucket | time ms | share |
|---|---:|---:|
| other (Enum/Map/:lists/:erlang BIFs, GenServer, ...) | 11594 | 39.2% |
| HEEx runtime: LiveView diff, engine, Phoenix.HTML escaping | 8434 | 28.5% |
| JSON encoding (Jason / JSON / serializer) | 3439 | 11.6% |
| message component and body render (Campfire web) | 1424 | 4.8% |
| Ash / Ecto / DB / notifiers | 1324 | 4.5% |
| websocket framing and writes (Bandit / ThousandIsland / port) | 1307 | 4.4% |
| render cache lookup / hashing | 1087 | 3.7% |
| RoomLive callbacks (Campfire web, other) | 924 | 3.1% |
| PubSub dispatch (Phoenix.PubSub, Registry) | 18 | 0.1% |

Top functions:

| function | calls | ms | share |
|---|---:|---:|---:|
| `:json.escape_binary/5` | 36165882 | 1584 | 5.4% |
| `Phoenix.HTML.Engine.html_escape/5` | 38949098 | 1500 | 5.1% |
| `:json.escape_binary_ascii/5` | 25350136 | 1009 | 3.4% |
| `:erts_internal.port_command/3` | 108172 | 758 | 2.6% |
| `List.last/2` | 15675627 | 580 | 2.0% |
| `:erlang.iolist_to_binary/1` | 728728 | 531 | 1.8% |
| `Enum.-map/2-lists^map/1-1-/2` | 6133464 | 530 | 1.8% |
| `:re.import/1` | 534668 | 523 | 1.8% |
| `:ets.lookup_element/4` | 780853 | 471 | 1.6% |
| `:erlang.send/2` | 408222 | 387 | 1.3% |
| `Phoenix.HTML.build_attrs/1` | 3914892 | 381 | 1.3% |
| `Enum.-reduce/3-lists^foldl/2-0-/3` | 4577002 | 364 | 1.2% |
| `Phoenix.HTML.Safe.Phoenix.LiveView.Rendered.recur_iodata/2` | 3238244 | 314 | 1.1% |
| `:erlang.++/2` | 658366 | 305 | 1.0% |
| `:gen_server.loop/5` | 410684 | 287 | 1.0% |
| `Plug.HTML.to_iodata/5` | 6695896 | 274 | 0.9% |
| `:maps.put/3` | 1936126 | 270 | 0.9% |
| `Phoenix.LiveView.Engine.changed_assign?/2` | 5969600 | 270 | 0.9% |
| `:erlang.integer_to_binary/1` | 1737972 | 256 | 0.9% |
| `Phoenix.LiveView.Engine.live_to_iodata/1` | 4847556 | 252 | 0.9% |
| `Phoenix.LiveView.Diff.traverse_dynamic/8` | 3344000 | 226 | 0.8% |
| `Phoenix.LiveView.Engine.nested_changed_assign?/4` | 2663464 | 223 | 0.8% |
| `:re.run/3` | 535295 | 198 | 0.7% |
| `:ets.lookup/2` | 655883 | 192 | 0.7% |
| `Phoenix.HTML.Safe.Phoenix.LiveView.Rendered.recur_iodata/1` | 2561596 | 178 | 0.6% |

