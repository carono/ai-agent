#!/usr/bin/env python3
"""Watch src/ for changes and rebuild dist/ automatically.

Uses only the standard library — no pip install needed.

Usage:
    python watch.py              # watch all, build all platforms
    python watch.py claude-code  # watch all, build only claude-code
    python watch.py opencode     # watch all, build only opencode
"""

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
SRC = os.path.join(ROOT, "src")
BUILD_SCRIPT = os.path.join(SCRIPT_DIR, "build.py")

POLL_INTERVAL = 1.0
DEBOUNCE = 0.5


def collect_mtimes(root: str) -> dict[str, float]:
    """Return {filepath: mtime} for every file under root."""
    result = {}
    for dirpath, _, filenames in os.walk(root):
        for fname in filenames:
            fpath = os.path.join(dirpath, fname)
            try:
                result[fpath] = os.path.getmtime(fpath)
            except OSError:
                pass
    return result


def run_build(platform: str | None, build_count: int) -> None:
    cmd = [sys.executable, BUILD_SCRIPT]
    if platform:
        cmd.append(platform)

    start = time.monotonic()
    result = subprocess.run(cmd, capture_output=False)
    elapsed = time.monotonic() - start
    print(f"Build #{build_count} completed in {elapsed:.2f}s")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "platform",
        nargs="?",
        choices=["claude-code", "opencode"],
        help="Build only this platform (default: all)",
    )
    args = parser.parse_args()

    print(f"Watching {os.path.relpath(SRC, ROOT)} for changes...")
    print("Press Ctrl+C to stop.\n")

    snapshots = collect_mtimes(SRC)
    build_count = 0
    last_build = 0.0

    try:
        while True:
            time.sleep(POLL_INTERVAL)
            now = time.monotonic()

            new_snapshots = collect_mtimes(SRC)
            changed = new_snapshots != snapshots

            if changed and (now - last_build) > DEBOUNCE:
                snapshots = new_snapshots
                build_count += 1
                last_build = now
                rel = set(new_snapshots.keys()) ^ set(snapshots.keys())
                if not rel:
                    rel = {"(modified)"}
                print(f"\n[{build_count}] Change detected: {', '.join(os.path.relpath(p, ROOT) for p in list(rel)[:3])}")
                run_build(args.platform, build_count)
                snapshots = collect_mtimes(SRC)

    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
