# Builds the load generator for Linux (the benchmark harness runs it inside a Linux VM/container).
#
#   docker build -t campfire-loadgen bench/loadgen
#   docker run --rm --network host campfire-loadgen liveview --base http://localhost:4000 ...
#
# Or only the binary (glibc, dynamically linked against libc only; runs on any recent distro):
#
#   docker build --target bin --output type=local,dest=bench/loadgen/out bench/loadgen   # -> out/loadgen
#
# Dependencies are fetched in their own layer, so editing src/ rebuilds in seconds.
FROM rust:1-slim-bookworm AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs \
 && cargo build --release --locked \
 && rm -rf src target/release/loadgen target/release/deps/loadgen*
COPY src ./src
RUN cargo build --release --locked && strip target/release/loadgen

# Just the binary, for `--output`.
FROM scratch AS bin
COPY --from=build /src/target/release/loadgen /loadgen

FROM debian:bookworm-slim
COPY --from=build /src/target/release/loadgen /usr/local/bin/loadgen
ENTRYPOINT ["/usr/local/bin/loadgen"]
