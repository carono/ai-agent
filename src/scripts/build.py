#!/usr/bin/env python3
"""Build dist/claude-code/ and dist/open-code/ from src/.

Converts JSON agent/tool definitions from src/ to platform-specific formats
using format.py, and copies static files (rules, templates).

Usage:
    python build.py
"""

import json
import os
import shutil
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
SRC = os.path.join(ROOT, "src")
DIST = os.path.join(ROOT, "dist")
FORMAT_SCRIPT = os.path.join(SCRIPT_DIR, "format.py")

PLATFORMS = ["claude-code", "opencode"]


def run_format(input_path: str, platform: str, output_path: str) -> None:
    """Run format.py to convert a JSON file to a platform format."""
    ext = ".md" if platform == "claude-code" else ".json"
    style = "markdown" if platform == "claude-code" else "json"

    cmd = [
        sys.executable, FORMAT_SCRIPT,
        input_path, platform,
        "--style", style,
        "--output", output_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ERROR: {result.stderr.strip()}", file=sys.stderr)
        return

    rel_in = os.path.relpath(input_path, ROOT)
    rel_out = os.path.relpath(output_path, ROOT)
    print(f"  {rel_in} -> {rel_out}")


def copy_dir(src_dir: str, dst_dir: str) -> int:
    """Copy all files from src_dir to dst_dir. Returns count."""
    if not os.path.isdir(src_dir):
        return 0

    os.makedirs(dst_dir, exist_ok=True)
    count = 0
    for fname in sorted(os.listdir(src_dir)):
        src_path = os.path.join(src_dir, fname)
        if os.path.isfile(src_path):
            dst_path = os.path.join(dst_dir, fname)
            shutil.copy2(src_path, dst_path)
            rel_in = os.path.relpath(src_path, ROOT)
            rel_out = os.path.relpath(dst_path, ROOT)
            print(f"  {rel_in} -> {rel_out} (copy)")
            count += 1
    return count


def build_platform(platform: str) -> int:
    """Build all files for a single platform. Returns count."""
    base = os.path.join(DIST, platform)
    total = 0

    # Convert agents
    agents_src = os.path.join(SRC, "agents")
    agents_dst = os.path.join(base, "agents")
    if os.path.isdir(agents_src):
        os.makedirs(agents_dst, exist_ok=True)
        for fname in sorted(os.listdir(agents_src)):
            if fname.endswith(".json"):
                ext = "md" if platform == "claude-code" else "json"
                out_name = fname.replace(".json", f".{ext}")
                run_format(
                    os.path.join(agents_src, fname),
                    platform,
                    os.path.join(agents_dst, out_name),
                )
                total += 1

    # Convert tools
    tools_src = os.path.join(SRC, "tools")
    tools_dst = os.path.join(base, "tools")
    if os.path.isdir(tools_src):
        os.makedirs(tools_dst, exist_ok=True)
        for fname in sorted(os.listdir(tools_src)):
            if fname.endswith(".json"):
                ext = "md" if platform == "claude-code" else "json"
                out_name = fname.replace(".json", f".{ext}")
                run_format(
                    os.path.join(tools_src, fname),
                    platform,
                    os.path.join(tools_dst, out_name),
                )
                total += 1

    # Copy static: rules
    rules_src = os.path.join(DIST, "rules")
    rules_dst = os.path.join(base, "rules")
    total += copy_dir(rules_src, rules_dst)

    # Copy static: templates
    templates_src = os.path.join(DIST, "templates")
    templates_dst = os.path.join(base, "templates")
    total += copy_dir(templates_src, templates_dst)

    return total


def main() -> None:
    print("Building dist/ from src/")
    total = 0

    for platform in PLATFORMS:
        print(f"\n[{platform}]")
        total += build_platform(platform)

    print(f"\nDone. {total} file(s) processed.")


if __name__ == "__main__":
    main()
