"""The measured suites (HTTP, LiveView fan-out, distinct-users fan-out, upload) and their preflight.

All loadgen flag spellings live in the `lg_*_args` functions so they are easy to reconcile with
bench/loadgen. Workloads are mapped from upstream's (see bench/README.md "Differences from upstream").
"""
import gzip, hashlib, http.client, json, os, re, subprocess, time, urllib.parse

import benchlib as B

# ---------------------------------------------------------------------------------------------------
# Python-side session handling (login and page scraping need no load generator)


def _request(method, path, headers=None, body=None, port=None):
    c = http.client.HTTPConnection(B.BASE_HOST, port or B.PORT, timeout=30)
    c.request(method, path, body=body, headers=headers or {})
    r = c.getresponse()
    data = r.read()
    h = {}
    for k, v in r.getheaders():
        h.setdefault(k.lower(), []).append(v)
    c.close()
    return r.status, h, data


def _cookies(headers):
    jar = {}
    for line in headers.get("set-cookie", []):
        k, _, rest = line.partition("=")
        jar[k] = rest.split(";", 1)[0]
    return jar


def _csrf(html):
    m = re.search(rb'name="_csrf_token"[^>]*value="([^"]+)"', html) or re.search(rb'value="([^"]+)"[^>]*name="_csrf_token"', html) \
        or re.search(rb'name="csrf-token"[^>]*content="([^"]+)"', html)
    return m.group(1).decode() if m else ""


def login(email, password, source=None):
    """Signs in through the real form; returns the Cookie header value."""
    status, h, body = _request("GET", "/session/new")
    assert status == 200, f"GET /session/new -> {status}"
    jar = _cookies(h)
    form = urllib.parse.urlencode({"_csrf_token": _csrf(body), "email_address": email, "password": password})
    status, h, _ = _request("POST", "/session", {
        "cookie": "; ".join(f"{k}={v}" for k, v in jar.items()),
        "content-type": "application/x-www-form-urlencoded",
    }, form)
    assert status == 302, f"login failed: {status} (is the seed user's password right? 10 sign-ins per 3 min per IP are allowed)"
    jar.update(_cookies(h))
    return "; ".join(f"{k}={v}" for k, v in jar.items())


def scrape_css(cookie, room):
    """The digested app.css URL the signed-in room page links to."""
    status, _, body = _request("GET", f"/rooms/{room}", {"cookie": cookie})
    assert status == 200, f"GET /rooms/{room} -> {status}"
    m = re.search(rb'href="(/assets/[^"]+\.css[^"]*)"', body)
    assert m, "no /assets/*.css link in the room page"
    return m.group(1).decode().replace("&amp;", "&")


# ---------------------------------------------------------------------------------------------------
# Workload mapping

SKIPPED = {"sidebar": "no HTTP endpoint in this app: LiveView renders the sidebar inside the page/socket"}


def routes(labels, css):
    """(name, kind, loadgen path or None) in upstream's order. kind: session | bot | static | post."""
    room, write_room = labels["busy_room"], labels["write_room"]
    key = labels["bot_key"]
    return [
        ("room_show", "session", f"/rooms/{room}"),
        ("messages_page", "bot", f"/rooms/{room}/{key}/messages?before={labels['before']}"),
        ("search", "session", f"/searches?q={urllib.parse.quote(labels['search_query'])}"),
        ("avatar", "session", f"/users/{labels['avatar_user']}/avatar"),
        ("static_css", "static", css),
        ("up", "static", "/up"),
        ("post_message", "post", write_room),
    ]


def lg_http_args(kind, path, cookie, labels):
    if kind == "post":   # POST through the bot API: the signed-in-form POST has no equivalent without CSRF/LiveView
        return ["--post-room", path, "--bot-key", labels["bot_key"]]
    args = ["--path", path]
    if kind in ("session", "static"):
        args += ["--cookie", cookie]
    return args


def lg_liveview_args(cookie, labels, clients, distinct_file=None):
    # --origin: the endpoint checks the Origin host against PHX_HOST=localhost, we connect to 127.0.0.1.
    args = ["--base", B.BASE, "--origin", "http://localhost", "--room", labels["busy_room"], "--clients", clients,
            "--tput-secs", B.CABLE_TPUT_SECS, "--posters", B.CABLE_POSTERS, "--bot-key", labels["bot_key"], *B.LIVEVIEW_ARGS]
    if distinct_file:    # sign-in is limited to 10 per 3 minutes per IP: each user signs in from its own X-Forwarded-For
        args += ["--distinct-users", distinct_file, "--spoof-ip", 1]
    else:
        args += ["--cookie", cookie]
    return args


def lg_upload_args(labels, cookie):
    # --cookie makes loadgen fetch the attachment thumbnail after each bot POST, as upstream's upload suite does.
    return ["--base", B.BASE, "--room", labels["write_room"], "--bot-key", labels["bot_key"], "--cookie", cookie,
            "--file", "/fixtures/black_hole.jpg", "--reps", B.UPLOAD_REPS]


# ---------------------------------------------------------------------------------------------------
# Preflight: reject redirects, errors, empty or unpopulated responses, keep response evidence

MESSAGE_MARKER = re.compile(rb'data-message-id="\d+"|id="message_\d+"')


def preflight(labels, cookie, rs, out_path):
    result = {}
    for name, kind, path in rs:
        if kind == "post":
            continue
        headers = {"accept-encoding": "gzip"}
        if kind in ("session", "static"):
            headers["cookie"] = cookie
        if kind == "bot":
            headers["accept"] = "application/json"
        status, h, data = _request("GET", path, headers)
        enc = (h.get("content-encoding") or [None])[0]
        body = gzip.decompress(data) if enc == "gzip" else data
        ctype = (h.get("content-type") or [""])[0]
        assert status == 200, (name, status, path)
        assert body, (name, "empty response")
        if name in ("room_show", "search"):
            assert MESSAGE_MARKER.search(body), (name, "populated message response required (see MESSAGE_MARKER in bench/lib/suites.py)")
        if name == "messages_page":
            msgs = json.loads(body)
            assert isinstance(msgs, list) and len(msgs) > 0, (name, "bot API returned no messages")
        if name == "avatar":
            assert ctype.startswith("image/") and len(body) > 50, (name, ctype, len(body))
        if name == "static_css":
            assert ctype.startswith("text/css") and b"{" in body, (name, ctype)
        if name == "up":
            assert body.strip() == b"OK", (name, body[:40])
        result[name] = {"status": status, "type": ctype, "encoding": enc, "wire_bytes": len(data), "body_bytes": len(body),
                        "body_sha256": hashlib.sha256(body).hexdigest()}
    # One bot POST proves the write path used by post_message, uploads and the fan-out posters.
    status, _, data = _request("POST", f"/rooms/{labels['write_room']}/{labels['bot_key']}/messages",
                               {"content-type": "text/plain"}, b"bench preflight")
    assert status == 201, ("bot POST", status, data[:200])
    busy = int(B.psql(f"SELECT count(*) FROM messages WHERE room_id = {labels['busy_room']}"))
    assert busy > 50, f"busy room {labels['busy_room']} has only {busy} messages"
    result["_busy_room_messages"] = busy
    json.dump({"passed": True, "responses": result}, open(out_path, "w"), indent=2)
    return result


# ---------------------------------------------------------------------------------------------------
# HTTP suite


def check_http(r, expected):
    assert r["errors"] == 0 and r.get("invalid_responses", 0) == 0 and set(r["statuses"]) == {expected}, r


def http_suite(cookie, labels, rs, cgs, log):
    out = []
    for name, kind, path in rs:
        args = lg_http_args(kind, path, cookie, labels)
        B.lg("http", "--base", B.BASE, *args, "--conc", 4, "--duration", 2)    # warm up
        for c in B.HTTP_CONCS:
            before = B.server_cpu(cgs)
            r = B.lg("http", "--base", B.BASE, *args, "--conc", c, "--duration", B.HTTP_SECS)
            after = B.server_cpu(cgs)
            check_http(r, "201" if kind == "post" else "200")
            r["cpu_us_per_success"] = sum(after[k] - before[k] for k in cgs) / r["ok"]
            for k in cgs:
                r[f"{k}_cpu_us_per_success"] = (after[k] - before[k]) / r["ok"]
            r["route"] = name
            out.append(r)
            log(f"{name} c={c} {r['rps']} rps p50 {r['latency'].get('p50_ms')} p99 {r['latency'].get('p99_ms')} {r['statuses']} err {r['errors']}")
    return out


# ---------------------------------------------------------------------------------------------------
# LiveView fan-out (shared by the single-user and distinct-users variants)


def check_fanout(r):
    assert r["ready"] == r["clients"] and r["failed"] == 0, r
    assert r["latency"]["complete"] == r["latency"]["messages"], r
    assert r["throughput"]["complete"] == r["throughput"]["posted"], r


def fanout_suite(label, clients_list, cookie, labels, cgs, log, distinct_file=None):
    out = []
    for n in clients_list:
        pm = os.path.join(B.WORK, f"{label}-{n}")
        sampler = subprocess.Popen(["taskset", "-c", B.PROCMEM_CPUS, "python3", os.path.join(B.BENCH, "lib", "procmem.py"), "sample", pm + ".jsonl", *cgs.values()])
        try:
            r, err = B.lg("liveview", *lg_liveview_args(cookie, labels, n, distinct_file), stderr=True)
        finally:
            time.sleep(0.5)
            sampler.terminate()
            sampler.wait()
        open(pm + ".stderr", "w").write(err)
        r["process_memory"] = json.loads(subprocess.run(
            ["python3", os.path.join(B.BENCH, "lib", "procmem.py"), "phases", pm + ".jsonl", pm + ".stderr"], capture_output=True, text=True, check=True).stdout)
        check_fanout(r)
        out.append(r)
        log(f"{label} {n} clients: ready {r['ready']} lat all p50 {r['latency']['all_clients'].get('p50_ms')} p99 {r['latency']['all_clients'].get('p99_ms')} "
            f"tput {r['throughput']['delivered_msgs_per_sec']} msg/s {r['throughput']['complete']}/{r['throughput']['posted']}")
        time.sleep(2)
    return out


def prepare_distinct_users(n, labels):
    """N extra active members of the busy room, all with the seeded user's password hash, so every client
    of the distinct-users fan-out is a different user. Returns the users file loadgen reads (--distinct-users):
    one `email password` per line, as loadgen's --distinct-users reads it (each user signs in once, with --spoof-ip, which the app
    honours only with TRUST_PROXY_HEADERS=1; see run_rep)."""
    room, email = labels["busy_room"], labels["email"]
    B.psql(f"""
      INSERT INTO users (id, name, email_address, password_hash, role, status, inserted_at, updated_at)
      SELECT m.base + g, 'Bench User ' || g, 'bench-user-' || g || '@example.com', t.password_hash, 'member', 'active', now(), now()
      FROM generate_series(1, {n}) g,
           (SELECT coalesce(max(id), 0) AS base FROM users) m,
           (SELECT password_hash FROM users WHERE email_address = '{email}') t;
      INSERT INTO memberships (id, involvement, room_id, user_id, inserted_at, updated_at)
      SELECT m.base + u.id - (SELECT min(id) FROM users WHERE email_address LIKE 'bench-user-%@example.com') + 1,
             'mentions', {room}, u.id, now(), now()
      FROM users u, (SELECT coalesce(max(id), 0) AS base FROM memberships) m
      WHERE u.email_address LIKE 'bench-user-%@example.com';
    """)
    path = os.path.join(B.WORK, "distinct-users.txt")
    with open(path, "w") as f:
        for i in range(1, n + 1):
            f.write(f"bench-user-{i}@example.com {labels['password']}\n")
    return "/work/distinct-users.txt"


# ---------------------------------------------------------------------------------------------------
# Upload, background jobs


def upload_suite(labels, cookie, log):
    r = B.lg("upload", *lg_upload_args(labels, cookie))
    assert all(x.get("post_status") in (200, 201) and x.get("thumb_status") == 200 and x.get("thumb_bytes", 0) > 100 and "error" not in x
               for x in r["runs"]), r
    log(f"upload median {r['median_total_ms']}ms")
    return r


def job_state():
    """Oban's queue at the end of the rep (upstream records its Resque backlog the same way)."""
    try:
        rows = B.psql("SELECT state || '=' || count(*) FROM oban_jobs GROUP BY state").split()
    except RuntimeError as e:
        return {"oban": False, "error": str(e)[:200]}
    states = {r.split("=")[0]: int(r.split("=")[1]) for r in rows}
    return {"queued": sum(states.get(s, 0) for s in ("available", "scheduled", "executing", "retryable")),
            "processed": states.get("completed", 0), "failed": states.get("discarded", 0), "states": states}
