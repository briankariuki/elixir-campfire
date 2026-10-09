"""Shared pieces for bench/run: knobs, docker/cgroup helpers, the fresh Postgres + app containers,
memory/CPU sampling and the load generator wrapper.

Method follows basecamp/once-campfire-elixir bench/run (MIT, see
bench/results/upstream-20261004/MIT-LICENSE.upstream): per rep and app a fresh datastore and a fresh
container from the production image, both pinned to SERVER_CPUS, the load generator pinned to
LOADGEN_CPUS, host networking, cgroup memory sampled every 200 ms.

Everything here runs on Linux with a docker CLI. On macOS bench/run re-executes itself inside the
harness container (bench/lib/harness.Dockerfile), see bench/README.md.
"""
import hashlib, json, os, re, shutil, socket, subprocess, sys, threading, time, urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BENCH = os.path.join(ROOT, "bench")
SEED = os.environ.get("SEED_DIR", os.path.join(BENCH, "seed", "default"))
FIXTURE = os.path.join(BENCH, "lib", "fixtures", "black_hole.jpg")


def env(name, default):
    return os.environ.get(name, str(default))


# --- Knobs (same names and defaults as upstream where the thing exists there) ---------------------
SERVER_CPUS = env("SERVER_CPUS", "0-3")      # Postgres + the app, together (upstream's app includes its datastore)
LOADGEN_CPUS = env("LOADGEN_CPUS", "4-7")
PROCMEM_CPUS = env("PROCMEM_CPUS", "8-9")    # the harness itself: samplers, polling, report
HTTP_SECS = env("HTTP_SECS", 8)
HTTP_CONCS = env("HTTP_CONCS", "1 16 64").split()
CABLE_CLIENTS = env("CABLE_CLIENTS", "100 500 1000").split()   # LiveView fan-out clients (name kept from upstream)
CABLE_TPUT_SECS = env("CABLE_TPUT_SECS", 15)
CABLE_POSTERS = env("CABLE_POSTERS", 4)
DISTINCT_CLIENTS = env("DISTINCT_CLIENTS", "100 500 1000").split()  # distinct-users fan-out: one user per client
UPLOAD_REPS = env("UPLOAD_REPS", 5)
PORT = int(env("PORT", 47130))
PG_PORT = int(env("PG_PORT", PORT + 1))
LOAD_MAX = float(env("LOAD_MAX", 1.5))
LOAD_WAIT_SECS = int(env("LOAD_WAIT_SECS", 900))
IDLE_SECS = int(env("IDLE_SECS", 10))
SUITES = env("SUITES", "http liveview upload").replace("cable", "liveview").split()   # + "distinct"
APP_IMAGE = env("APP_IMAGE", "campfire-port:bench")
PG_IMAGE = env("PG_IMAGE", "postgres:17")
PG_ARGS = env("PG_ARGS", "").split()          # extra `postgres -c ...` arguments (recorded in env.txt)
LOADGEN_IMAGE = env("LOADGEN_IMAGE", "campfire-loadgen:bench")
LOADGEN_ENTRYPOINT = env("LOADGEN_ENTRYPOINT", "loadgen")
APP_EXTRA_ENV = env("APP_EXTRA_ENV", "").split()   # K=V for every app container; per variant: APP_EXTRA_ENV_<NAME>
LIVEVIEW_ARGS = env("LIVEVIEW_ARGS", "").split()   # extra loadgen flags for the fan-out suites, e.g. "--deflate 1"
SECRET_KEY_BASE = env("SECRET_KEY_BASE", "bench-" + "0123456789abcdef" * 6)
PG_PASSWORD = "bench"
BASE_HOST = env("BASE_HOST", "127.0.0.1")     # must be localhost or 127.0.0.1: config/prod.exs exempts them from force_ssl
BASE = f"http://{BASE_HOST}:{PORT}"
WORK = os.path.join(BENCH, ".work", str(PORT))
RUN_LABEL = f"campfire-bench={PORT}"
APP_NAME = f"bench-app-{PORT}"
PG_NAME = f"bench-pg-{PORT}"
VOLUME = f"bench-uploads-{PORT}"
DATABASE_URL = f"ecto://campfire:{PG_PASSWORD}@127.0.0.1:{PG_PORT}/campfire"

# Label keys in bench/seed/default/labels.json (the upstream parity seed's, preserved by the importer).
# A value starting with "=" is a literal. One place to adjust.
LABEL_KEYS = {
    "email": "emails.david",              # the signed-in user (administrator, member of every room below)
    "password": "passwords.all",
    "busy_room": "rooms.watercooler",     # upstream's busy room: GETs and the fan-out posts go here
    "write_room": "rooms.hq",             # HTTP post_message and uploads go here, so the busy room stays put
    "before": "messages.busy_060",        # a page in the middle of the busy room
    "avatar_user": "users.jason",         # has an uploaded image avatar
    "search_query": "=coffee",            # upstream's query (not in labels.json)
    "bot_key": "bot_keys.bender",         # "<id>-<token>"; bender is a member of the watercooler only
    "bot_id": "users.bender",
}


def cpu_count(cpulist):
    """Number of CPUs in a list like "0-3,8"."""
    n = 0
    for part in cpulist.split(","):
        lo, _, hi = part.partition("-")
        n += int(hi or lo) - int(lo) + 1
    return n


def log(*a):
    print(time.strftime("[%H:%M:%S]"), *a, file=sys.stderr, flush=True)


# --- Subprocess helpers ---------------------------------------------------------------------------

def run(cmd, check=True, stdin=None, timeout=None, input=None):
    p = subprocess.run(cmd, stdin=stdin, input=input, capture_output=True, text=True, timeout=timeout)
    if check and p.returncode != 0:
        raise RuntimeError(f"{' '.join(map(str, cmd))[:300]} failed ({p.returncode}): {(p.stderr or p.stdout)[-1500:]}")
    return p


def docker(*args, **kw):
    return run(["docker", *map(str, args)], **kw)


def image_id(image):
    p = docker("image", "inspect", "-f", "{{.Id}} {{.Created}} unpacked_bytes={{.Size}}", image, check=False)
    return p.stdout.strip() if p.returncode == 0 else f"{image} (not found)"


def image_exists(image):
    return docker("image", "inspect", image, check=False).returncode == 0


def loadavg():
    return open("/proc/loadavg").read().split()[:3]


def port_free(port):
    with socket.socket() as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def wait_for_quiet():
    """Waits for the 1-minute load average to drop below LOAD_MAX, for at most LOAD_WAIT_SECS."""
    waited = 0
    while float(loadavg()[0]) >= LOAD_MAX and waited < LOAD_WAIT_SECS:
        time.sleep(10)
        waited += 10
    log(f"load before run: {' '.join(loadavg())} (waited {waited}s)")


# --- Source / seed identity -----------------------------------------------------------------------

SOURCE_PATHS = ["lib", "config", "priv", "assets", "rel", "mix.exs", "mix.lock", "Dockerfile"]


def source_digest():
    """git rev + dirty flag for what goes into the image (BENCH_SOURCE_DIGEST is computed on the host
    by the macOS launcher, where the worktree's git dir is reachable)."""
    if os.environ.get("BENCH_SOURCE_DIGEST"):
        return os.environ["BENCH_SOURCE_DIGEST"]
    try:
        g = lambda *a: subprocess.run(["git", "-C", ROOT, *a], capture_output=True, text=True, check=True).stdout
        rev = g("rev-parse", "HEAD").strip()
        status = g("status", "--porcelain", "--", *SOURCE_PATHS).splitlines()
        diff = hashlib.sha256((g("diff", "HEAD", "--", *SOURCE_PATHS)).encode()).hexdigest()[:12] if status else ""
        return f"{rev} (dirty: {len(status)} files{', diff sha256 ' + diff if status else ''})"
    except Exception as e:  # noqa: BLE001
        return f"unknown ({e})"


def seed_digest():
    out = []
    for name in ("campfire.sql", "labels.json"):
        p = os.path.join(SEED, name)
        if os.path.exists(p):
            h = hashlib.sha256()
            with open(p, "rb") as f:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    h.update(chunk)
            out.append(f"{h.hexdigest()}  {name}")
    up = os.path.join(SEED, "uploads")
    if os.path.isdir(up):
        h, n = hashlib.sha256(), 0
        for d, _, files in sorted(os.walk(up)):
            for fn in sorted(files):
                p = os.path.join(d, fn)
                h.update(os.path.relpath(p, up).encode())
                h.update(str(os.path.getsize(p)).encode())
                n += 1
        out.append(f"{h.hexdigest()}  uploads/ ({n} files, names+sizes)")
    return out


class Labels:
    def __init__(self, path):
        self.data = json.load(open(path))

    def get(self, key):
        if key.startswith("="):
            return key[1:]
        if key in self.data:                  # the upstream seed's labels.json is flat: {"rooms.hq": 201306877, ...}
            return str(self.data[key])
        node = self.data                      # ...but accept nested objects too
        for part in key.split("."):
            if not isinstance(node, dict) or part not in node:
                near = [k for k in self.data if k.split(".")[0] == key.split(".")[0]][:8]
                raise KeyError(f"labels.json has no '{key}' (similar: {near}); adjust LABEL_KEYS in bench/lib/benchlib.py")
            node = node[part]
        return str(node)

    def __getitem__(self, name):
        return self.get(LABEL_KEYS[name])


# --- Containers -----------------------------------------------------------------------------------

def cleanup():
    for name in (APP_NAME, PG_NAME):
        docker("rm", "-f", name, check=False)
    docker("volume", "rm", "-f", VOLUME, check=False)


def cgroup_dir(name):
    cid = docker("inspect", "-f", "{{.Id}}", name).stdout.strip()
    for cand in (f"/sys/fs/cgroup/docker/{cid}", f"/sys/fs/cgroup/system.slice/docker-{cid}.scope"):
        if os.path.isdir(cand):
            return cand
    raise RuntimeError(f"no cgroup directory for {name} ({cid}); the harness needs /sys/fs/cgroup and --cgroupns host")


def read_int(path):
    try:
        return int(open(path).read().strip())
    except (OSError, ValueError):
        return 0


def mem_anon(cg):
    try:
        for line in open(f"{cg}/memory.stat"):
            if line.startswith("anon "):
                return int(line.split()[1])
    except OSError:
        pass
    return 0


def cpu_usec(cg):
    try:
        for line in open(f"{cg}/cpu.stat"):
            if line.startswith("usage_usec"):
                return int(line.split()[1])
    except OSError:
        pass
    return 0


MB = 1048576


class Sampler(threading.Thread):
    """Samples memory.current and anon of the given cgroups every 200 ms and keeps the maxima, of the
    sum (what the server side holds at once) and of each cgroup."""

    def __init__(self, cgs):
        super().__init__(daemon=True)
        self.cgs, self.running = cgs, True
        self.peak_cur = self.peak_anon = 0
        self.peak_each = {k: [0, 0] for k in cgs}

    def run(self):
        while self.running:
            cur = anon = 0
            for k, cg in self.cgs.items():
                c, a = read_int(f"{cg}/memory.current"), mem_anon(cg)
                cur, anon = cur + c, anon + a
                self.peak_each[k] = [max(self.peak_each[k][0], c), max(self.peak_each[k][1], a)]
            self.peak_cur, self.peak_anon = max(self.peak_cur, cur), max(self.peak_anon, anon)
            time.sleep(0.2)

    def stop(self):
        self.running = False
        self.join()

    def result(self):
        out = {"peak_current_mb": self.peak_cur // MB, "peak_anon_mb": self.peak_anon // MB}
        for k, (c, a) in self.peak_each.items():
            out[f"{k}_peak_current_mb"], out[f"{k}_peak_anon_mb"] = c // MB, a // MB
        return out


def memory_now(cgs):
    cur = {k: read_int(f"{cg}/memory.current") for k, cg in cgs.items()}
    anon = {k: mem_anon(cg) for k, cg in cgs.items()}
    return cur, anon


def server_cpu(cgs):
    return {k: cpu_usec(cg) for k, cg in cgs.items()}


def start_postgres():
    docker("rm", "-f", PG_NAME, check=False)
    docker("run", "-d", "--name", PG_NAME, "--label", RUN_LABEL, "--cpuset-cpus", SERVER_CPUS, "--network", "host",
           "-e", "POSTGRES_USER=campfire", "-e", f"POSTGRES_PASSWORD={PG_PASSWORD}", "-e", "POSTGRES_DB=campfire",
           PG_IMAGE, "-c", f"port={PG_PORT}", *PG_ARGS)
    # TCP, not the socket: the init-time temporary server only listens on the socket.
    for _ in range(600):
        if docker("exec", PG_NAME, "pg_isready", "-h", "127.0.0.1", "-p", PG_PORT, "-U", "campfire", "-d", "campfire", check=False).returncode == 0:
            return
        time.sleep(0.2)
    raise RuntimeError("postgres did not become ready:\n" + docker("logs", "--tail", 30, PG_NAME, check=False).stderr)


def psql(sql=None, file=None, capture=True):
    cmd = ["docker", "exec", "-i", PG_NAME, "psql", "-h", "127.0.0.1", "-p", str(PG_PORT), "-U", "campfire", "-d", "campfire",
           "-v", "ON_ERROR_STOP=1", "-q", "-At"]
    if sql is not None:
        return run(cmd + ["-c", sql]).stdout.strip()
    with open(file, "rb") as f:
        p = subprocess.run(cmd, stdin=f, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"psql {file} failed: {p.stderr[-1500:]}")
    return p.stdout


def app_env_args(name, extra=()):
    args = []
    env_ = {
        "PORT": str(PORT), "DATABASE_URL": DATABASE_URL, "SECRET_KEY_BASE": SECRET_KEY_BASE, "PHX_HOST": "localhost",
        "UPLOADS_DIR": "/data/uploads",
    }
    for kv in [*APP_EXTRA_ENV, *os.environ.get("APP_EXTRA_ENV_" + re.sub(r"\W", "_", name).upper(), "").split(), *extra]:
        k, _, v = kv.partition("=")
        env_[k] = v
    for k, v in env_.items():
        args += ["-e", f"{k}={v}"]
    return args


def migrate(image, name):
    """`/app/bin/migrate` against the fresh empty database, pinned like the app; returns its wall ms."""
    t0 = time.monotonic()
    docker("run", "--rm", "--init", "--network", "host", "--cpuset-cpus", SERVER_CPUS, *app_env_args(name), image, "/app/bin/migrate")
    return round((time.monotonic() - t0) * 1000)


def seed_tweaks(labels):
    """Bench-only addition to the seed: the bot API answers 404 unless the bot is a member of the room, and
    the seed's bot (bender) is only in the watercooler, so add it to the write room (rooms.hq)."""
    bot, room = labels["bot_id"], labels["write_room"]
    psql(f"""INSERT INTO memberships (id, involvement, room_id, user_id, inserted_at, updated_at)
             SELECT coalesce(max(id), 0) + 1, 'nothing', {room}, {bot}, now(), now() FROM memberships
             WHERE NOT EXISTS (SELECT 1 FROM memberships WHERE room_id = {room} AND user_id = {bot})""")


def load_data():
    """Seed SQL into the migrated DB, then VACUUM ANALYZE (planner statistics, as a settled production DB
    would have), and the seed uploads into a fresh volume with the image's own ownership."""
    psql(file=os.path.join(SEED, "campfire.sql"))
    psql("VACUUM ANALYZE")
    psql("CHECKPOINT")
    docker("volume", "create", "--label", RUN_LABEL, VOLUME)
    uploads = os.path.join(SEED, "uploads")
    copy = "chown -R nobody:root /data/uploads"
    mounts = []
    if os.path.isdir(uploads) and os.listdir(uploads):
        mounts = ["-v", f"{uploads}:/seed-uploads:ro"]
        copy = "cp -a /seed-uploads/. /data/uploads/ && " + copy
    docker("run", "--rm", "--user", "root", "-v", f"{VOLUME}:/data/uploads", *mounts, "--entrypoint", "sh", APP_IMAGE, "-c", copy)


def http_up(timeout=1.0):
    try:
        return urllib.request.urlopen(f"{BASE}/up", timeout=timeout).status == 200
    except Exception:  # noqa: BLE001
        return False


def start_app(image, name, extra_env=()):
    """docker run -> /up 200, in ms. The database and uploads are already loaded."""
    docker("rm", "-f", APP_NAME, check=False)
    os.sync()
    t0 = time.monotonic()
    docker("run", "-d", "--name", APP_NAME, "--label", RUN_LABEL, "--init", "--cpuset-cpus", SERVER_CPUS, "--network", "host",
           *app_env_args(name, extra_env), "-v", f"{VOLUME}:/data/uploads", image)
    for _ in range(3000):
        if http_up():
            return round((time.monotonic() - t0) * 1000)
        time.sleep(0.02)
    raise RuntimeError("app did not come up:\n" + docker("logs", "--tail", 40, APP_NAME, check=False).stdout)


# --- Load generator -------------------------------------------------------------------------------
USER_AGENT_ARGS = []


def lg(*args, stderr=False, extra_mounts=()):
    """Runs one loadgen command in a container pinned to LOADGEN_CPUS; returns the parsed JSON (and stderr)."""
    os.makedirs(WORK, exist_ok=True)
    cmd = ["docker", "run", "--rm", "--network", "host", "--cpuset-cpus", LOADGEN_CPUS, "--ulimit", "nofile=1048576:1048576",
           "-v", f"{WORK}:/work", "-v", f"{os.path.dirname(FIXTURE)}:/fixtures:ro", "-v", f"{SEED}:/seed:ro", *extra_mounts,
           "--entrypoint", LOADGEN_ENTRYPOINT, LOADGEN_IMAGE, *map(str, args), *USER_AGENT_ARGS]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"loadgen {args[0]} failed ({p.returncode}): {p.stderr[-2000:]}")
    out = json.loads(p.stdout)
    return (out, p.stderr) if stderr else out
