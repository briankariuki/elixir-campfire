# Fan-out profile: profile-fanout-20261007-micro2

`run.json`: {  "clients": 500,  "rate": 80.0,  "secs": 10,  "image": "campfire-port:micro2",  "cpu": {   "untraced": {    "app_cpu_s": 22.317091,    "db_cpu_s": 0.854666   },   "targeted": {    "app_cpu_s": 16.598719,    "db_cpu_s": 0.625113   }  } }

## Untraced window

```
%{
  memory: [
    total: 1063407860,
    processes: 880540064,
    processes_used: 879997640,
    system: 182867796,
    atom: 2622361,
    atom_used: 2622361,
    binary: 43637296,
    code: 80254483,
    ets: 9425464
  ],
  processes: 1591,
  reductions: 661690106,
  schedulers_online: 4,
  json_library: JSON,
  window_secs: 10,
  gcs: 138020,
  gc_words_reclaimed: 1076501627,
  io_input_bytes: 1346057,
  io_output_bytes: 2496282806
}
```

Scheduler wall time (`:scheduler.utilization`): weighted 48.0% of the online schedulers (total over all 30 incl. offline: 9.6%); busy normal schedulers 1:50% 2:47% 3:49% 4:46%

Microstate accounting, normal schedulers that ran (10), share of wall time and of busy time:

| state | % of wall | % of busy |
|---|---:|---:|
| sleep | 78.5% | - |
| emulator | 12.7% | 59.3% |
| other | 4.2% | 19.5% |
| port | 2.1% | 9.7% |
| gc | 1.5% | 7.2% |
| check_io | 0.6% | 2.9% |
| aux | 0.3% | 1.4% |

Reductions by process class (top):

```
other (CampfireWeb.RoomLive)                                      500 procs      426537057 reductions 64.5%
Bandit/ThousandIsland connection (websocket transport)            501 procs      229291748 reductions 34.7%
other (:erpc)                                                       1 procs        4725560 reductions 0.7%
other (DBConnection.ConnectionPool)                                 1 procs         245363 reductions 0.0%
other (:user_drv)                                                   1 procs         105717 reductions 0.0%
other (:group)                                                      1 procs         101803 reductions 0.0%
```

## Targeted tprof (call_time on boundary functions)

`deliveries` = LiveView renders in the window = 366000. us/delivery = time of the function / deliveries (the per-viewer cost of one posted message).

| function | calls | total ms | us/call | us/delivery |
|---|---:|---:|---:|---:|
| `ThousandIsland.Socket.send/2` | 367233 | 2538 | 6.9 | 6.9 |
| `CampfireWeb.MessageBody.Cache.fetch/3` | 732732 | 1932 | 2.6 | 5.3 |
| `Ash.create/3` | 732 | 1547 | 2114.2 | 4.2 |
| `Phoenix.LiveView.Diff.render/4` | 366000 | 1516 | 4.1 | 4.1 |
| `Registry.dispatch/4` | 2929 | 1329 | 453.9 | 3.6 |
| `Phoenix.LiveView.Channel.push/3` | 366000 | 893 | 2.4 | 2.4 |
| `CampfireWeb.RoomLive.handle_info/2` | 366000 | 681 | 1.9 | 1.9 |
| `CampfireWeb.RoomLive.append_messages/2` | 366000 | 656 | 1.8 | 1.8 |
| `Phoenix.LiveView.Channel.render_diff/3` | 732000 | 614 | 0.8 | 1.7 |
| `Phoenix.LiveView.Channel.handle_info/2` | 732000 | 503 | 0.7 | 1.4 |
| `Campfire.Notifiers.Fanout.notify/1` | 732 | 362 | 495.9 | 1.0 |
| `CampfireWeb.RoomLive.decorate/2` | 366000 | 309 | 0.8 | 0.8 |
| `Phoenix.LiveView.Lifecycle.after_render/1` | 366000 | 200 | 0.5 | 0.5 |
| `Bandit.WebSocket.Connection.handle_info/3` | 366000 | 181 | 0.5 | 0.5 |
| `CampfireWeb.MessageBody.digest/2` | 366732 | 135 | 0.4 | 0.4 |
| `JSON.encode_to_iodata!/2` | 367966 | 122 | 0.3 | 0.3 |
| `Phoenix.LiveView.Renderer.to_rendered/2` | 366000 | 107 | 0.3 | 0.3 |
| `Phoenix.LiveView.Diff.render_private/2` | 732000 | 97 | 0.1 | 0.3 |
| `CampfireWeb.RoomLive.render/1` | 366000 | 87 | 0.2 | 0.2 |
| `Campfire.Chat.create_message/3` | 732 | 78 | 106.6 | 0.2 |
| `CampfireWeb.BotMessageController.create/2` | 732 | 77 | 105.4 | 0.2 |
| `Bandit.WebSocket.Handler.handle_info/2` | 366000 | 70 | 0.2 | 0.2 |
| `Bandit.WebSocket.Frame.serialize/1` | 366500 | 65 | 0.2 | 0.2 |
| `Phoenix.LiveView.Utils.clear_changed/1` | 366000 | 57 | 0.2 | 0.2 |
| `JSON.encode_to_iodata!/1` | 367966 | 54 | 0.1 | 0.1 |
| `CampfireWeb.RoomLive.stop_typing/2` | 366000 | 51 | 0.1 | 0.1 |
| `CampfireWeb.RoomLive.maybe_play_sound/2` | 366000 | 46 | 0.1 | 0.1 |
| `Phoenix.Socket.__info__/2` | 366000 | 39 | 0.1 | 0.1 |

### Where one delivery goes (targeted tprof, us per delivery; tracing only ~40 functions, so close to real)

| bucket | us/delivery | share of traced |
|---|---:|---:|
| JSON encoding (serializer) | 0.5 | 1.3% |
| LiveView diff and render (Diff.render, RoomLive.render) | 7.3 | 18.9% |
| message component render (MessageComponents, emoji_only?) | 0.0 | 0.1% |
| render cache lookup and hashing (Cache.fetch, digest) | 5.7 | 14.6% |
| hand the frame to the transport (Channel.push: send/copy) | 2.4 | 6.3% |
| websocket framing and socket write (Bandit, ThousandIsland) | 7.9 | 20.4% |
| LiveView callbacks (handle_info, stream insert, window, sound) | 6.1 | 15.8% |
| PubSub dispatch (Registry.dispatch, per post / viewers) | 3.6 | 9.4% |
| Ash create + notifiers (per post / viewers) | 5.2 | 13.4% |
| traced total | 38.8 | |
| **all threads busy, untraced window (incl. GC, port, scheduling, the poster's Ash/PubSub work)** | 55.4 | (80 msgs/s x 500 clients x 10 s = 400000 deliveries) |

