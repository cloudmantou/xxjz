#!/usr/bin/env python3
"""Validate the signed device artifact, not just source entitlements. Does not print credentials."""
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / "Info.plist").read_bytes())
result = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(app)], capture_output=True, check=True)
entitlements = plistlib.loads(result.stdout)
checks = {
    "app bundle": info.get("CFBundleIdentifier") == "com.assetlife.app",
    "CloudKit capability": "CloudKit" in entitlements.get("com.apple.developer.icloud-services", []),
    "CloudKit container": "iCloud.com.assetlife.app" in entitlements.get("com.apple.developer.icloud-container-identifiers", []),
    "APNs entitlement": entitlements.get("aps-environment") in ("development", "production"),
    "background notifications": "remote-notification" in info.get("UIBackgroundModes", []),
}
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if not all(checks.values()):
    sys.exit(1)
