#!/usr/bin/env python3
"""Per-process memory of the server-side containers, by role, while a fan-out run goes on.

Adapted from basecamp/once-campfire-elixir bench/lib/procmem.py (MIT, see
bench/results/upstream-20261004/MIT-LICENSE.upstream).

  procmem.py sample OUT.jsonl CGROUP_DIR [CGROUP_DIR ...]   # every 250 ms until killed or the cgroups go
  procmem.py phases OUT.jsonl LOADGEN.stderr                # peak per role within each loadgen PHASE window
                                                            # (and the cores busy per cgroup: cpu_cores = [app, db])

Roles, from each process's command line: `beam` (the Erlang VM running the Phoenix release, plus its
tiny helpers erl_child_setup/epmd/inet_gethost), `postgres` (the postmaster and every backend and
auxiliary process), `other`. Each sample sums, per role, Pss (proportional set size, so pages shared
between forked processes count once) and Anonymous (anonymous resident memory, counted in every
process that maps it), both from /proc/PID/smaps_rollup, in MB. Needs a PID namespace that sees the
containers' processes (the harness container runs with --pid host).
"""
import json, os, re, sys, time


def role(cmdline):
    if "beam.smp" in cmdline or "erl_child_setup" in cmdline or "epmd" in cmdline or "inet_gethost" in cmdline:
        return "beam"
    if "postgres" in cmdline:
        return "postgres"
    return "other"


def rollup(pid):
    out = {}
    with open(f"/proc/{pid}/smaps_rollup") as f:
        for line in f:
            k, _, v = line.partition(":")
            if k in ("Pss", "Anonymous"):
                out[k] = int(v.split()[0]) / 1024
    return out


def snapshot(cgroups):
    """{role: {pss_mb, anon_mb, procs}} over every process in `cgroups` (None when all are gone)."""
    roles, alive = {}, False
    for cgroup in cgroups:
        try:
            pids = open(f"{cgroup}/cgroup.procs").read().split()
        except OSError:
            continue
        alive = True
        for pid in pids:
            try:
                cmd = open(f"/proc/{pid}/cmdline").read().replace("\0", " ")
                m = rollup(pid)
            except OSError:
                continue
            r = roles.setdefault(role(cmd), {"pss_mb": 0.0, "anon_mb": 0.0, "procs": 0})
            r["pss_mb"] += m.get("Pss", 0)
            r["anon_mb"] += m.get("Anonymous", 0)
            r["procs"] += 1
    return roles if alive else None


def cpu_usec(cgroup):
    try:
        for line in open(f"{cgroup}/cpu.stat"):
            if line.startswith("usage_usec"):
                return int(line.split()[1])
    except OSError:
        pass
    return 0


def sample(path, cgroups):
    with open(path, "w") as out:
        while True:
            roles = snapshot(cgroups)
            if roles is None:
                break
            # cpu: cumulative CPU time (us) of each cgroup, in the order given (app, db)
            out.write(json.dumps({"t": int(time.time() * 1000), "roles": roles, "cpu": [cpu_usec(c) for c in cgroups]}) + "\n")
            out.flush()
            time.sleep(0.25)


def phases(path, stderr_path):
    samples = [json.loads(l) for l in open(path) if l.strip()]
    marks = [(m.group(1), int(m.group(2))) for m in re.finditer(r"PHASE (\w+) (\d+)", open(stderr_path).read())]
    bounds = marks + [("after", 10**15)]
    result = {}
    for (name, t0), (_, t1) in zip(bounds, bounds[1:]):
        window = [s for s in samples if s["t"] < t0][-1:] + [s for s in samples if t0 <= s["t"] < t1]
        if not window:
            continue
        roles = {}
        for s in window:
            for r, v in s["roles"].items():
                cur = roles.setdefault(r, {"peak_pss_mb": 0.0, "peak_anon_mb": 0.0})
                cur["peak_pss_mb"] = round(max(cur["peak_pss_mb"], v["pss_mb"]), 1)
                cur["peak_anon_mb"] = round(max(cur["peak_anon_mb"], v["anon_mb"]), 1)
                cur["procs"] = v["procs"]
        total = max(sum(v["pss_mb"] for v in s["roles"].values()) for s in window)
        result[name] = {"roles": roles, "peak_total_pss_mb": round(total, 1)}
        first, last = window[0], window[-1]
        if len(window) > 1 and "cpu" in first and "cpu" in last and last["t"] > first["t"]:
            secs = (last["t"] - first["t"]) / 1000
            # cores busy over the window, per cgroup (app, db) from the first to the last sample inside it
            result[name]["cpu_cores"] = [round((b - a) / 1e6 / secs, 3) for a, b in zip(first["cpu"], last["cpu"])]
            result[name]["cpu_window_secs"] = round(secs, 2)
    return result


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "sample":
        sample(sys.argv[2], sys.argv[3:])
    elif len(sys.argv) == 4 and sys.argv[1] == "phases":
        print(json.dumps(phases(sys.argv[2], sys.argv[3])))
    else:
        sys.exit(__doc__)
