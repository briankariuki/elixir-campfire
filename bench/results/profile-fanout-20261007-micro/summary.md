# Fan-out profile: profile-fanout-20261007-micro

`run.json`: {  "clients": 500,  "rate": 80.0,  "secs": 10,  "image": "campfire-port:micro",  "cpu": {   "untraced": {    "app_cpu_s": 21.993328,    "db_cpu_s": 0.863392   },   "targeted": {    "app_cpu_s": 16.292881,    "db_cpu_s": 0.635921   }  } }

## Untraced window

```
%{
  memory: [
    total: 1187392256,
    processes: 1004290584,
    processes_used: 1003753304,
    system: 183101672,
    atom: 2622337,
    atom_used: 2622337,
    binary: 43906368,
    code: 80253255,
    ets: 9416656
  ],
  processes: 1591,
  reductions: 661352848,
  schedulers_online: 4,
  json_library: JSON,
  window_secs: 10,
  gcs: 138178,
  gc_words_reclaimed: 1290420908,
  io_input_bytes: 1341512,
  io_output_bytes: 2489610237
}
```

Scheduler wall time (`:scheduler.utilization`): weighted 46.7% of the online schedulers (total over all 30 incl. offline: 9.3%); busy normal schedulers 1:46% 2:45% 3:47% 4:48%

Microstate accounting, normal schedulers that ran (10), share of wall time and of busy time:

| state | % of wall | % of busy |
|---|---:|---:|
| sleep | 79.0% | - |
| emulator | 12.6% | 60.0% |
| other | 4.1% | 19.6% |
| port | 2.1% | 9.8% |
| gc | 1.4% | 6.6% |
| check_io | 0.6% | 2.7% |
| aux | 0.3% | 1.3% |

Reductions by process class (top):

```
other (CampfireWeb.RoomLive)                                      500 procs      427413185 reductions 64.6%
Bandit/ThousandIsland connection (websocket transport)            501 procs      228714627 reductions 34.6%
other (:erpc)                                                       1 procs        4728287 reductions 0.7%
other (DBConnection.ConnectionPool)                                 1 procs         244310 reductions 0.0%
other (:user_drv)                                                   1 procs         105582 reductions 0.0%
other (:group)                                                      1 procs         102165 reductions 0.0%
```

## Targeted tprof (call_time on boundary functions)

`deliveries` = LiveView renders in the window = 365622. us/delivery = time of the function / deliveries (the per-viewer cost of one posted message).

| function | calls | total ms | us/call | us/delivery |
|---|---:|---:|---:|---:|
| `ThousandIsland.Socket.send/2` | 366763 | 2450 | 6.7 | 6.7 |
| `CampfireWeb.MessageBody.Cache.fetch/3` | 731937 | 2032 | 2.8 | 5.6 |
| `Ash.create/3` | 731 | 1511 | 2068.4 | 4.1 |
| `CampfireWeb.RoomLive.append_messages/2` | 365622 | 1410 | 3.9 | 3.9 |
| `Registry.dispatch/4` | 2925 | 1330 | 454.9 | 3.6 |
| `Phoenix.LiveView.Diff.render/4` | 365622 | 1175 | 3.2 | 3.2 |
| `Phoenix.LiveView.Channel.push/3` | 365583 | 943 | 2.6 | 2.6 |
| `Phoenix.LiveView.Channel.handle_info/2` | 731122 | 485 | 0.7 | 1.3 |
| `CampfireWeb.RoomLive.handle_info/2` | 365622 | 466 | 1.3 | 1.3 |
| `Phoenix.LiveView.Channel.render_diff/3` | 731122 | 412 | 0.6 | 1.1 |
| `Campfire.Notifiers.Fanout.notify/1` | 731 | 389 | 532.4 | 1.1 |
| `Phoenix.LiveView.Lifecycle.after_render/1` | 365583 | 226 | 0.6 | 0.6 |
| `Bandit.WebSocket.Connection.handle_info/3` | 365532 | 183 | 0.5 | 0.5 |
| `Phoenix.LiveView.Utils.clear_changed/1` | 365583 | 155 | 0.4 | 0.4 |
| `CampfireWeb.MessageBody.digest/2` | 366354 | 138 | 0.4 | 0.4 |
| `CampfireWeb.RoomLive.decorate/2` | 365622 | 132 | 0.4 | 0.4 |
| `JSON.encode_to_iodata!/2` | 367544 | 122 | 0.3 | 0.3 |
| `Phoenix.LiveView.Diff.render_private/2` | 731083 | 107 | 0.1 | 0.3 |
| `Phoenix.LiveView.Renderer.to_rendered/2` | 365622 | 106 | 0.3 | 0.3 |
| `CampfireWeb.RoomLive.render/1` | 365622 | 87 | 0.2 | 0.2 |
| `CampfireWeb.BotMessageController.create/2` | 731 | 77 | 105.3 | 0.2 |
| `Campfire.Chat.create_message/3` | 731 | 74 | 101.5 | 0.2 |
| `Bandit.WebSocket.Frame.serialize/1` | 366032 | 67 | 0.2 | 0.2 |
| `Bandit.WebSocket.Handler.handle_info/2` | 365532 | 65 | 0.2 | 0.2 |
| `CampfireWeb.RoomLive.stop_typing/2` | 365622 | 45 | 0.1 | 0.1 |
| `CampfireWeb.RoomLive.maybe_play_sound/2` | 365622 | 43 | 0.1 | 0.1 |
| `JSON.encode_to_iodata!/1` | 367544 | 42 | 0.1 | 0.1 |
| `Phoenix.Socket.__info__/2` | 365532 | 39 | 0.1 | 0.1 |

### Where one delivery goes (targeted tprof, us per delivery; tracing only ~40 functions, so close to real)

| bucket | us/delivery | share of traced |
|---|---:|---:|
| JSON encoding (serializer) | 0.5 | 1.2% |
| LiveView diff and render (Diff.render, RoomLive.render) | 6.2 | 16.0% |
| message component render (MessageComponents, emoji_only?) | 0.0 | 0.1% |
| render cache lookup and hashing (Cache.fetch, digest) | 5.9 | 15.3% |
| hand the frame to the transport (Channel.push: send/copy) | 2.6 | 6.6% |
| websocket framing and socket write (Bandit, ThousandIsland) | 7.7 | 19.8% |
| LiveView callbacks (handle_info, stream insert, window, sound) | 7.1 | 18.2% |
| PubSub dispatch (Registry.dispatch, per post / viewers) | 3.6 | 9.4% |
| Ash create + notifiers (per post / viewers) | 5.2 | 13.4% |
| traced total | 38.8 | |
| **all threads busy, untraced window (incl. GC, port, scheduling, the poster's Ash/PubSub work)** | 54.3 | (80 msgs/s x 500 clients x 10 s = 400000 deliveries) |

