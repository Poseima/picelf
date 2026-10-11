import base64
import copy
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("validate_update", ROOT / "scripts/release/validate-update.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class UpdateReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.archive = self.directory / "Picelf-1.1.0-universal.dmg"
        self.archive.write_bytes(b"synthetic update archive")
        self.feed = self.directory / "appcast.xml"
        self.url = "https://github.com/Poseima/picelf-open/releases/download/v1.1.0/" + self.archive.name
        self.info = dict(CFBundleVersion="2", CFBundleShortVersionString="1.1.0", LSMinimumSystemVersion="14.0",
                         SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
                         SUEnableInstallerLauncherService=True, SUAllowsAutomaticUpdates=False, SUAutomaticallyUpdate=False)
        self.write_feed()

    def write_feed(self, **changes):
        values = dict(build="2", version="1.1.0", minimum="14.0.0", url=self.url,
                      length=str(self.archive.stat().st_size), signature=base64.b64encode(bytes(64)).decode())
        values.update(changes)
        root = ET.Element("rss")
        item = ET.SubElement(ET.SubElement(root, "channel"), "item")
        for key in ["version", "shortVersionString", "minimumSystemVersion"]:
            ET.SubElement(item, module.SPARKLE + key).text = values[dict(version="build", shortVersionString="version", minimumSystemVersion="minimum")[key]]
        ET.SubElement(item, "description").text = "更新说明 / Release notes"
        ET.SubElement(item, "enclosure", {"url": values["url"], "length": values["length"], module.SPARKLE + "edSignature": values["signature"]})
        ET.ElementTree(root).write(self.feed, encoding="utf-8", xml_declaration=True)

    def test_valid_feed_matches_exact_archive(self):
        self.assertTrue(module.validate_appcast(self.feed, self.archive, self.info, self.url))

    def test_rejects_mismatched_versions_sizes_and_download_urls(self):
        for values in [dict(build="1"), dict(version="1.0.0"), dict(minimum="15.0"), dict(length="1"),
                       dict(url=self.url.replace("v1.1.0", "latest")), dict(signature="")]:
            with self.subTest(values=values):
                self.write_feed(**values)
                with self.assertRaises(ValueError):
                    module.validate_appcast(self.feed, self.archive, self.info, self.url)

    def test_rejects_missing_signature_policies_and_silent_installation(self):
        for key in ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUEnableInstallerLauncherService",
                    "SUAllowsAutomaticUpdates", "SUAutomaticallyUpdate"]:
            info = copy.deepcopy(self.info)
            info[key] = not info[key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                module.validate_appcast(self.feed, self.archive, info, self.url)

    def test_rejects_beta_delta_and_missing_notes(self):
        for change in ["channel", "deltas", "description"]:
            self.write_feed()
            tree = ET.parse(self.feed)
            item = tree.find("./channel/item")
            if change == "description":
                item.remove(item.find("description"))
            else:
                ET.SubElement(item, module.SPARKLE + change).text = "beta"
            tree.write(self.feed)
            with self.assertRaises(ValueError):
                module.validate_appcast(self.feed, self.archive, self.info, self.url)

    def test_only_published_stable_releases_constrain_versions(self):
        pages = [[dict(tag_name="v1.0.0", draft=False, prerelease=False),
                  dict(tag_name="v99.0.0", draft=True, prerelease=False)],
                 [dict(tag_name="v98.0.0", draft=False, prerelease=True)]]
        self.assertEqual(module.previous_tag(pages, "1.1.0"), "v1.0.0")
        for version in ["1.0.0", "0.9.9"]:
            with self.assertRaises(ValueError):
                module.previous_tag(pages, version)
        self.assertEqual(module.previous_tag([[]], "1.0.0"), "")

    def test_build_number_never_repeats_or_decreases(self):
        module.validate_build(self.info, dict(CFBundleVersion="1"))
        for value in ["2", "3"]:
            with self.assertRaises(ValueError):
                module.validate_build(self.info, dict(CFBundleVersion=value))
        for value in ["0", "-1", "1.0", "invalid"]:
            with self.assertRaises(ValueError):
                module.validate_build(dict(CFBundleVersion=value), None)

    def test_official_signer_rejects_modified_feed_and_archive(self):
        tools = ROOT / ".build/packages/artifacts/sparkle/Sparkle/bin"
        signer = tools / "sign_update"
        if not signer.exists():
            self.skipTest("Resolve the pinned Sparkle package to run cryptographic tool checks")
        # Deliberately public synthetic key, never the production signing key.
        key = self.directory / "test-only.key"
        key.write_text(base64.b64encode(bytes(range(32))).decode())
        os.chmod(key, 0o600)
        prefix = [str(signer), "--ed-key-file", str(key)]
        signature = subprocess.check_output(prefix + ["-p", str(self.archive)], text=True).strip()
        subprocess.run(prefix + ["--verify", str(self.archive), signature], check=True, capture_output=True)
        self.archive.write_bytes(b"modified archive")
        self.assertNotEqual(subprocess.run(prefix + ["--verify", str(self.archive), signature], capture_output=True).returncode, 0)
        subprocess.run(prefix + [str(self.feed)], check=True, capture_output=True)
        subprocess.run(prefix + ["--verify", str(self.feed)], check=True, capture_output=True)
        self.feed.write_bytes(self.feed.read_bytes().replace(b"1.1.0", b"9.9.9"))
        self.assertNotEqual(subprocess.run(prefix + ["--verify", str(self.feed)], capture_output=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
