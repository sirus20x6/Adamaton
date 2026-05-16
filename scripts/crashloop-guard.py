#!/usr/bin/env python3
"""Detect docker containers in a restart loop and stop them.

Polls `docker ps -a` for RestartCount per container, keeps a small
sliding-window history per container in $STATE_FILE, and `docker stop`s
any container whose RestartCount climbed by more than $THRESHOLD inside
$WINDOW_SECONDS.

Why this exists: 2026-05-15, the deepresearch-searxng-1 container went
into a crashloop (settings.yml schema regression). Over ~2.5 hours it
restarted 154 times. Each restart created+destroyed a veth pair and a
netns; the kernel eventually exhausted some network resource and froze
the Pi hard, requiring a power-cycle. This guard auto-stops the next
runaway container before it can do that.

Designed to be a systemd timer target -- one shot, exit on its own.
Logs to journald via stdout; systemd captures it.

Env knobs:
  STATE_FILE      where the sliding-window history is persisted
                  (default /var/lib/crashloop-guard/state.json)
  THRESHOLD       max restarts allowed inside the window (default 5)
  WINDOW_SECONDS  sliding-window size (default 120)
  DRY_RUN         if "1", print what would be stopped, don't act
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

STATE_FILE = Path(os.environ.get("STATE_FILE", "/var/lib/crashloop-guard/state.json"))
THRESHOLD = int(os.environ.get("THRESHOLD", "5"))
WINDOW_SECONDS = int(os.environ.get("WINDOW_SECONDS", "120"))
DRY_RUN = os.environ.get("DRY_RUN", "") == "1"


def docker_inspect_all() -> list[dict]:
    # docker ps -a returns every container, running or not. We poll the
    # whole list so a container that exited+is restarting at sample time
    # still gets accounted for.
    out = subprocess.run(
        ["docker", "ps", "-a", "--no-trunc", "--format", "{{.ID}}"],
        capture_output=True,
        text=True,
        check=True,
    )
    ids = [line for line in out.stdout.splitlines() if line]
    if not ids:
        return []
    raw = subprocess.run(
        ["docker", "inspect", *ids],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(raw.stdout)


def load_state() -> dict:
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        # Corrupt state is recoverable -- we just lose one window of history.
        return {}


def save_state(state: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, sort_keys=True))
    tmp.replace(STATE_FILE)


def main() -> int:
    now = int(time.time())
    cutoff = now - WINDOW_SECONDS
    state = load_state()
    seen_ids: set[str] = set()

    for c in docker_inspect_all():
        cid = c["Id"]
        seen_ids.add(cid)
        name = c["Name"].lstrip("/")
        restart_count = int(c.get("RestartCount") or 0)

        entry = state.setdefault(cid, {"name": name, "samples": []})
        entry["name"] = name  # may have been renamed
        samples: list[list[int]] = entry["samples"]
        samples.append([now, restart_count])
        # Trim samples older than the window. Keep at least one for delta math.
        entry["samples"] = [s for s in samples if s[0] >= cutoff] or [samples[-1]]

        # Compute the delta over the trimmed window.
        oldest = entry["samples"][0][1]
        delta = restart_count - oldest
        if delta <= THRESHOLD:
            continue

        # Crashloop. Stop the container and reset its history so we don't
        # double-fire after the next poll.
        log(
            f"crashloop detected: name={name} delta={delta} window={WINDOW_SECONDS}s"
            f" threshold={THRESHOLD} restart_count={restart_count}"
        )
        if DRY_RUN:
            log(f"DRY_RUN: would `docker stop {name}`")
        else:
            try:
                subprocess.run(
                    ["docker", "stop", "--time", "5", cid],
                    check=True,
                    capture_output=True,
                    timeout=30,
                )
                log(f"stopped {name}")
            except subprocess.CalledProcessError as e:
                log(f"failed to stop {name}: rc={e.returncode} stderr={e.stderr.decode(errors='replace')}")
            except subprocess.TimeoutExpired:
                log(f"timeout stopping {name}")
        # Reset window so the next poll doesn't redundantly trip on the
        # same restart spike if `docker stop` is slow / the user restarts
        # the container by hand.
        entry["samples"] = [[now, restart_count]]

    # Garbage-collect entries for containers no longer present.
    for cid in list(state.keys()):
        if cid not in seen_ids:
            del state[cid]

    save_state(state)
    return 0


def log(msg: str) -> None:
    print(msg, flush=True)


if __name__ == "__main__":
    sys.exit(main())
