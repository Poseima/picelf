#!/usr/bin/env python3
"""Validate update metadata against the exact signed application and archive."""
import argparse
import base64
import json
from pathlib import Path
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def version_tuple(version):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Expected a MAJOR.MINOR.PATCH release version")
    return tuple(map(int, version.split(".")))


def build_number(info):
    value = str(info.get("CFBundleVersion", ""))
    if not re.fullmatch(r"[1-9][0-9]*", value):
        raise ValueError("Build number must be a positive, monotonically increasing integer")
    return int(value)


def stable_releases(pages):
    return [release for page in pages for release in page
            if not release["draft"] and not release["prerelease"]]


def previous_tag(pages, candidate_version):
    current = version_tuple(candidate_version)
    published = []
    for release in stable_releases(pages):
        tag = release["tag_name"]
        if not tag.startswith("v"):
            raise ValueError("Published stable release has an unexpected version tag")
        version = version_tuple(tag[1:])
        if version >= current:
            raise ValueError("Candidate version must exceed every published stable version")
        published.append((version, tag))
    return max(published)[1] if published else ""


def validate_build(candidate, previous):
    build = build_number(candidate)
    if previous and build <= build_number(previous):
        raise ValueError("Candidate build number must exceed the previous official build")


def read_previous_app(dmg, team):
    mount_data = subprocess.check_output(["hdiutil", "attach", "-readonly", "-nobrowse", "-plist", str(dmg)])
    mounts = [entry["mount-point"] for entry in plistlib.loads(mount_data)["system-entities"] if "mount-point" in entry]
    try:
        if len(mounts) != 1:
            raise ValueError("Expected one previous-release volume")
        app = Path(mounts[0]) / "Picelf.app"
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        signature = subprocess.run(["codesign", "-dv", "--verbose=4", str(app)], check=True,
                                   capture_output=True, text=True).stderr
        if f"TeamIdentifier={team}\n" not in signature or "Authority=Developer ID Application:" not in signature:
            raise ValueError("Previous release signing team differs from the candidate")
        with (app / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        if info.get("CFBundleIdentifier") != "com.picelf.open.app":
            raise ValueError("Previous release has an unexpected application identifier")
        return info
    finally:
        for mount in mounts:
            subprocess.run(["hdiutil", "detach", mount], check=True, stdout=subprocess.DEVNULL)


def validate_appcast(feed, archive, info, download_url):
    root = ET.parse(feed).getroot()
    items = root.findall("./channel/item")
    if len(items) != 1:
        raise ValueError("Stable v1 feed must contain exactly one full update")
    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None or enclosure.get("url") != download_url or not download_url.startswith("https://"):
        raise ValueError("Update URL must refer to the exact versioned release archive")
    if item.findtext(SPARKLE + "version") != str(info["CFBundleVersion"]):
        raise ValueError("Appcast build disagrees with the application")
    if item.findtext(SPARKLE + "shortVersionString") != info["CFBundleShortVersionString"]:
        raise ValueError("Appcast marketing version disagrees with the application")
    minimum = item.findtext(SPARKLE + "minimumSystemVersion", "")
    # Sparkle may normalize 14.0 to 14.0.0.
    normalize = lambda value: tuple(map(int, (value.split(".") + ["0", "0"])[:3]))
    if normalize(minimum) != normalize(info["LSMinimumSystemVersion"]):
        raise ValueError("Minimum system version disagrees with the application")
    if int(enclosure.get("length", "0")) != archive.stat().st_size:
        raise ValueError("Appcast archive size disagrees with the final DMG")
    signature = enclosure.get(SPARKLE + "edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("Missing valid Ed25519 archive signature")
    if item.find(SPARKLE + "deltas") is not None or item.find(SPARKLE + "channel") is not None:
        raise ValueError("Only full, stable updates are allowed")
    if not item.findtext("description", "").strip():
        raise ValueError("Embedded release notes are required")
    for key in ("SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUEnableInstallerLauncherService"):
        if info.get(key) is not True:
            raise ValueError(f"Required updater setting missing: {key}")
    if info.get("SUAllowsAutomaticUpdates") is not False or info.get("SUAutomaticallyUpdate") is not False:
        raise ValueError("Installation must remain user initiated")
    return signature


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prior = commands.add_parser("previous-tag")
    prior.add_argument("releases", type=Path)
    prior.add_argument("version")
    inspect = commands.add_parser("inspect-previous")
    inspect.add_argument("dmg", type=Path)
    inspect.add_argument("team")
    inspect.add_argument("output", type=Path)
    build = commands.add_parser("build")
    build.add_argument("info", type=Path)
    build.add_argument("--previous", type=Path)
    feed = commands.add_parser("appcast")
    feed.add_argument("feed", type=Path)
    feed.add_argument("archive", type=Path)
    feed.add_argument("info", type=Path)
    feed.add_argument("url")
    args = parser.parse_args()
    if args.command == "previous-tag":
        print(previous_tag(json.loads(args.releases.read_text()), args.version))
    elif args.command == "inspect-previous":
        args.output.write_bytes(plistlib.dumps(read_previous_app(args.dmg, args.team)))
    else:
        info = plistlib.loads(args.info.read_bytes())
        if args.command == "build":
            previous = plistlib.loads(args.previous.read_bytes()) if args.previous else None
            validate_build(info, previous)
        else:
            print(validate_appcast(args.feed, args.archive, info, args.url))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, ET.ParseError) as error:
        raise SystemExit(f"Update validation failed: {error}")
