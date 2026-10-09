# Comparison

A = `bench/results/campfire-20261007`, B = `bench/results/campfire-tuned-20261007`. Medians over reps. ×: B ÷ A.

**Warning: the runs' knobs differ**, so the numbers are not matched:

- A: `workload: suites=http liveview upload HTTP_SECS=4 HTTP_CONCS=1 16 64 CABLE_CLIENTS=100 500 1000 CABLE_TPUT_SECS=15 CABLE_POSTERS=4 DISTINCT_CLIENTS=100 500 1000 UPLOAD_REPS=5 IDLE_SECS=10 REPS=2`
  B: `workload: suites=http liveview HTTP_SECS=4 HTTP_CONCS=1 16 64 CABLE_CLIENTS=100 500 1000 CABLE_TPUT_SECS=15 CABLE_POSTERS=4 DISTINCT_CLIENTS=100 500 1000 UPLOAD_REPS=5 IDLE_SECS=10 REPS=2`

## campfire (2 reps vs 2 reps)

| Throughput | A | B | × |
|---|---:|---:|---:|
| room_show req/s (c=64) | 380.1 | 459.9 | 1.21× |
| messages_page req/s (c=64) | 507.4 | 523.1 | 1.03× |
| search req/s (c=64) | 1,342.4 | 1,398.1 | 1.04× |
| avatar req/s (c=64) | 4,135.2 | 4,420.9 | 1.07× |
| static_css req/s (c=64) | 31,141.9 | 31,624.2 | 1.02× |
| up req/s (c=64) | 39,989.9 | 44,006.9 | 1.10× |
| post_message req/s (c=64) | 357.1 | 375.5 | 1.05× |
| LiveView fan-out 100 clients, msgs/s delivered to all | 116.5 | 276.7 | 2.37× |
| LiveView fan-out 500 clients, msgs/s delivered to all | 35.5 | 132.1 | 3.73× |
| LiveView fan-out 1000 clients, msgs/s delivered to all | 19.2 | 79.2 | 4.11× |

| Latency (p50 ms, c=64) | A | B | × |
|---|---:|---:|---:|
| room_show | 167.30 | 138.81 | 0.83× |
| messages_page | 124.67 | 120.64 | 0.97× |
| search | 46.99 | 45.36 | 0.97× |
| avatar | 15.22 | 14.22 | 0.93× |
| static_css | 1.86 | 1.85 | 0.99× |
| up | 1.36 | 1.27 | 0.94× |
| post_message | 168.89 | 159.87 | 0.95× |

| Cost | A | B | × |
|---|---:|---:|---:|
| Cold start (ms) | 1,340.0 | 1,225.0 | 0.91× |
| Idle anonymous memory (MiB) | 279.0 | 292.0 | 1.05× |
| Peak anonymous memory (MiB) | 3,244.0 | 2,164.5 | 0.67× |
| Peak memory.current (MiB) | 3,369.0 | 2,299.5 | 0.68× |
| room_show CPU µs/success (c=64) | 9,995.4 | 8,200.5 | 0.82× |
| messages_page CPU µs/success (c=64) | 7,557.4 | 7,349.0 | 0.97× |
| search CPU µs/success (c=64) | 2,862.3 | 2,742.7 | 0.96× |
| avatar CPU µs/success (c=64) | 895.9 | 862.1 | 0.96× |
| static_css CPU µs/success (c=64) | 119.4 | 118.2 | 0.99× |
| up CPU µs/success (c=64) | 62.7 | 58.4 | 0.93× |
| post_message CPU µs/success (c=64) | 4,290.3 | 3,985.4 | 0.93× |

End-of-run Oban queue counts (accepted writes can precede job completion):

| Run | Queued | Processed | Failed |
|---|---:|---:|---:|
| campfire-20261007 / campfire-1 | 0 | 0 | 0 |
| campfire-20261007 / campfire-2 | 0 | 0 | 0 |
| campfire-tuned-20261007 / campfire-1 | 0 | 0 | 0 |
| campfire-tuned-20261007 / campfire-2 | 0 | 0 | 0 |

