# The benchmark harness's own container (macOS/OrbStack): bench/run re-executes itself in here so that
# taskset, /proc, /proc/loadavg and the containers' cgroups (/sys/fs/cgroup/docker/<id>) are visible,
# as upstream's bench/run needs on Linux. It drives the engine through the mounted docker socket.
FROM docker.io/library/docker:cli AS dockercli

FROM docker.io/library/debian:trixie-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 util-linux procps curl git ca-certificates \
  && rm -rf /var/lib/apt/lists/*
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
RUN git config --system --add safe.directory '*'
