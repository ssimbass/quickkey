#!/usr/bin/env python3
"""Check the explicit source distribution without reading files outside this project."""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
TOP_FILES = {"Package.swift", "README.md", "LICENSE", "CONTRIBUTING.md", "SECURITY.md", "CHANGELOG.md", ".gitignore"}
PUBLIC_DIRS = {"Sources", "Tests", "scripts", "Assets", "docs", ".github"}
PATTERNS = {
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "GitHub token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{40,})\b"),
    "cloud access key": re.compile(r"\bAKIA[A-Z0-9]{16}\b"),
    "API secret": re.compile(r"\bsk-[A-Za-z0-9]{32,}\b"),
    "local user path": re.compile(r"/(?:Users|home)/[A-Za-z0-9_.-]+/"),
}


def source_files():
    if (ROOT / ".git").is_dir():
        result = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
                                cwd=ROOT, check=True, capture_output=True)
        paths = [Path(p.decode()) for p in result.stdout.split(b"\0") if p]
    else:
        paths = [p.relative_to(ROOT) for p in ROOT.rglob("*") if p.is_file()
                 and (p.relative_to(ROOT).parts[0] in PUBLIC_DIRS or p.relative_to(ROOT).as_posix() in TOP_FILES)
                 and ".DS_Store" not in p.parts and "__pycache__" not in p.parts]
    return sorted(set(paths))


def main():
    failures = []
    files = source_files()
    for path in files:
        file = ROOT / path
        if file.is_symlink():
            failures.append((path, "symlink excluded from public sources"))
            continue
        if path.parts[0] in {".build", "dist", ".swiftpm", ".credentials"} or path.name.startswith(".env") or path.suffix in {".key", ".pem", ".p12", ".log"}:
            failures.append((path, "local or sensitive artifact"))
            continue
        data = file.read_bytes()
        if path.suffix.lower() in {".png", ".icns"}:
            expected = b"\x89PNG\r\n\x1a\n" if path.suffix.lower() == ".png" else b"icns"
            if not data.startswith(expected):
                failures.append((path, "invalid image format"))
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            failures.append((path, "unexpected binary file"))
            continue
        for label, pattern in PATTERNS.items():
            if pattern.search(text):
                failures.append((path, label))
    for path, reason in failures:
        print(f"FAIL: {path}: {reason}")
    if failures:
        return 1
    print(f"Public source checks passed: {len(files)} files; no known token, private key, personal home path, or build artifact patterns found.")
    print("Pattern checks cannot guarantee absence of every secret; review staged files before publication.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
