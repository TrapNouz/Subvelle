"""Prints the next Subvelle version: the patch number counts 0-9, then the minor number goes up.

  1.3.0 -> 1.3.1 -> ... -> 1.3.9 -> 1.4.0 -> ... -> 1.9.9 -> 2.0.0

Usage:
  python3 Tools/next_version.py 1.3.9     # prints 1.4.0
  python3 Tools/next_version.py           # next after the highest vX.Y.Z tag on origin
"""
import re, subprocess, sys

def next_version(version: str) -> str:
    major, minor, patch = (int(p) for p in version.lstrip("vV").split("."))
    patch += 1
    if patch > 9: patch, minor = 0, minor + 1
    if minor > 9: minor, major = 0, major + 1
    return f"{major}.{minor}.{patch}"

def latest_tag() -> str:
    out = subprocess.run(["git", "ls-remote", "--tags", "origin"], capture_output=True, text=True, check=True).stdout
    tags = {tuple(map(int, m)) for m in re.findall(r"refs/tags/v(\d+)\.(\d+)\.(\d+)$", out, re.M)}
    if not tags: sys.exit("no vX.Y.Z tags found on origin")
    return ".".join(map(str, max(tags)))

if __name__ == "__main__":
    assert next_version("1.3.0") == "1.3.1" and next_version("1.3.9") == "1.4.0" and next_version("1.9.9") == "2.0.0"
    print(next_version(sys.argv[1] if len(sys.argv) > 1 else latest_tag()))
