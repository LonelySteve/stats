#!/usr/bin/env python3
"""Run the mihomo API contract tests using the macOS Command Line Tools.

An optional path to a saved /providers/proxies response also validates that
response. Tests use URLProtocol and never connect to the configured router.
"""
from pathlib import Path
import subprocess
import os
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]

with tempfile.TemporaryDirectory(prefix="stats-mihomo-tests-") as directory:
    binary = Path(directory) / "mihomo-tests"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        "-module-cache-path", str(Path(directory) / "cache"),
        str(ROOT / "Modules/Mihomo/api.swift"), str(ROOT / "Tests/Mihomo.swift"),
        "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary), *sys.argv[1:]], check=True)

    # A process-local interposer verifies Security calls without touching real Keychain items.
    library = Path(directory) / "keychain-test.dylib"
    subprocess.run([
        "clang", "-dynamiclib", "-framework", "Security", "-framework", "CoreFoundation",
        str(ROOT / "Tests/MihomoKeychain.c"), "-o", str(library),
    ], check=True)
    keychain_binary = Path(directory) / "keychain-tests"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        "-module-cache-path", str(Path(directory) / "cache"),
        str(ROOT / "Modules/Mihomo/api.swift"), str(ROOT / "Tests/MihomoKeychain.swift"),
        "-o", str(keychain_binary),
    ], check=True)
    subprocess.run([str(keychain_binary)], check=True,
                   env={**os.environ, "DYLD_INSERT_LIBRARIES": str(library)})
