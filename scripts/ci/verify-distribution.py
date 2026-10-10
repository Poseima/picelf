#!/usr/bin/env python3
"""Validate invariants needed to ship a standalone, freely usable application."""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parents[2]
errors = []
for path in (root / "Sources").rglob("*"):
    if path.is_file() and path.suffix in {".swift", ".storekit"}:
        source = path.read_text()
        if path.suffix == ".storekit" or re.search(r"\b(StoreKit|StoreManager|TrialManager|AccessGate|PurchaseView|PurchaseWindowController)\b", source):
            errors.append(f"Unexpected feature-unlock code: {path.relative_to(root)}")
        if "private let microphonePermissionTeamIdentifier" in source:
            errors.append(f"Hardcoded signing team: {path.relative_to(root)}")
project = (root / "project.yml").read_text()
for bundle_id in ("com.picelf.open.app", "com.picelf.open.ios", "com.picelf.open.ios.broadcast-upload"):
    if f"PRODUCT_BUNDLE_IDENTIFIER: {bundle_id}\n" not in project:
        errors.append(f"Missing app identity {bundle_id}")
if "DEVELOPMENT_TEAM:" in project:
    errors.append("Default project must not require a particular development team")
for target in ("Picelf", "PicelfIOS"):
    info = plistlib.loads((root / f"Sources/{target}/Info.plist").read_bytes())
    if info.get("CFBundleDisplayName") != "Picelf":
        errors.append(f"Wrong display name for {target}")
app_group = "group.com.picelf.open.shared"
for target in ("PicelfIOS", "PicelfBroadcastUpload"):
    ent = plistlib.loads((root / f"Sources/{target}/{target}.entitlements").read_bytes())
    if ent.get("com.apple.security.application-groups") != [app_group]:
        errors.append(f"Wrong shared App Group for {target}")
for name in ("Sources/PicelfIOS/Capture/BroadcastFrameRelay.swift", "Sources/PicelfBroadcastUpload/SampleHandler.swift"):
    if f'"{app_group}"' not in (root / name).read_text():
        errors.append(f"App Group code and entitlement disagree: {name}")
if '"com.picelf.open.ios.broadcast-upload"' not in (root / "Sources/PicelfIOS/Views/BroadcastPickerView.swift").read_text():
    errors.append("Broadcast picker does not match the extension")
for name in ("LICENSE", "licenses/KeyboardShortcuts.txt", "licenses/SnapshotTesting.txt"):
    path = root / name
    if not path.is_file() or "Permission is hereby granted" not in path.read_text():
        errors.append(f"Missing license notice: {name}")
if errors:
    raise SystemExit("\n".join(errors))
print("Distribution invariants passed: identity, shared group, licenses, no feature-unlock code")
