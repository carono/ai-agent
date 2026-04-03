#!/usr/bin/env python3
"""Build dist/<platform>/ from src/.

For each platform (claude-code, opencode):
  1. Converts src/agents/*.md and src/tools/*.md via format.py
  2. Copies src/rules/ and src/templates/ into dist/<platform>/

Usage:
    python build.py              # build all platforms
    python build.py claude-code  # build only claude-code
    python build.py opencode     # build only opencode
"""

import argparse
import os
import shutil
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
SRC = os.path.join(ROOT, "src")
DIST = os.path.join(ROOT, "dist")
FORMAT_SCRIPT = os.path.join(SCRIPT_DIR, "format.py")

ALL_PLATFORMS = ["claude-code", "opencode"]


def clean_platform_dir(platform: str):
    """Remove dist/<platform>/ if it exists."""
    path = os.path.join(DIST, platform)
    if os.path.isdir(path):
        shutil.rmtree(path)


def copy_dir(src_dir: str, dst_dir: str) -> int:
    """Copy all files from src_dir to dst_dir. Returns count."""
    if not os.path.isdir(src_dir):
        print(f"  SKIP: {src_dir} not found")
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
            print(f"  {rel_in} -> {rel_out}")
            count += 1
    return count


def run_format(input_path: str, platform: str, output_path: str) -> bool:
    """Run format.py to convert a Markdown file to a platform format."""
    ext = ".md"
    style = "markdown"

    cmd = [
        sys.executable, FORMAT_SCRIPT,
        input_path, platform,
        "--style", style,
        "--output", output_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ERROR: {result.stderr.strip()}", file=sys.stderr)
        return False

    rel_in = os.path.relpath(input_path, ROOT)
    rel_out = os.path.relpath(output_path, ROOT)
    print(f"  {rel_in} -> {rel_out}")
    return True


def build_platform(platform: str) -> int:
    """Build dist/<platform>/ from src/. Returns file count."""
    base = os.path.join(DIST, platform)
    total = 0

    # Step 1: Convert agents and tools via format.py
    agents_src = os.path.join(SRC, "agents")
    agents_dst = os.path.join(base, "agents")
    if os.path.isdir(agents_src):
        os.makedirs(agents_dst, exist_ok=True)
        for fname in sorted(os.listdir(agents_src)):
            if fname.endswith(".md"):
                if run_format(
                    os.path.join(agents_src, fname),
                    platform,
                    os.path.join(agents_dst, fname),
                ):
                    total += 1

    tools_src = os.path.join(SRC, "tools")
    tools_dst = os.path.join(base, "tools")
    if os.path.isdir(tools_src):
        os.makedirs(tools_dst, exist_ok=True)
        for fname in sorted(os.listdir(tools_src)):
            if fname.endswith(".md"):
                if run_format(
                    os.path.join(tools_src, fname),
                    platform,
                    os.path.join(tools_dst, fname),
                ):
                    total += 1

    # Step 2: Copy rules and templates
    total += copy_dir(os.path.join(SRC, "rules"), os.path.join(base, "rules"))
    total += copy_dir(os.path.join(SRC, "templates"), os.path.join(base, "templates"))

    return total


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "platform",
        nargs="?",
        choices=ALL_PLATFORMS,
        help="Build only this platform (default: all)",
    )
    args = parser.parse_args()

    platforms = [args.platform] if args.platform else ALL_PLATFORMS

    print("Building dist/ from src/")

    total = 0

    for platform in platforms:
        print(f"\n[{platform}]")
        clean_platform_dir(platform)
        total += build_platform(platform)

    print(f"\nDone. {total} file(s) processed.")


if __name__ == "__main__":
    main()
