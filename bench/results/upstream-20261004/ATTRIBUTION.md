# Upstream reference results

These files are an unmodified copy of `bench/results/ruby-elixir-go-rust-20261004/` from
[basecamp/once-campfire-elixir](https://github.com/basecamp/once-campfire-elixir) (commit
`f15fc9eb609286f1e3da970e7dfd95e3bf69f82f`), published under the MIT license (`MIT-LICENSE.upstream`,
Copyright (c) 37signals, LLC). They are kept here so that `bench/report DIR --with-upstream` can put this
port's medians next to upstream's published Rails, Elixir, Go and Rust medians.

Measured by upstream on 2026-10-04: AMD RYZEN AI MAX+ 395 (32 threads, 30 GB), Linux 7.2.5, server CPUs 8-11,
load generator CPUs 12-15, host networking, two reps per version (see `env*.txt` and `report.md`). Do not
edit these files; add new runs as sibling directories under `bench/results/`.
