#!/usr/bin/env python3
"""Render actual SwiftUI views in both appearances without changing system settings."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
binary = root / "build" / "RenderPreviews"
binary.parent.mkdir(exist_ok=True)
sources = sorted(str(p) for p in (root / "AIUsage").rglob("*.swift") if p.name != "AIUsageApp.swift")
subprocess.run([
    "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
    *sources, str(root / "scripts" / "RenderPreviews.swift"), "-o", str(binary)
], check=True, cwd=root)
subprocess.run([str(binary), str(root / "build" / "previews"), *sys.argv[1:]], check=True, cwd=root)
