"""Run the actual updater shell blocks offline; requires bash, jq and PyYAML."""

import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest

import yaml


REPO = Path(__file__).resolve().parents[1]
WORKFLOW = REPO / ".github/workflows/update-hermes-desktop.yml"
STEPS = {
    step["name"]: step["run"]
    for step in yaml.safe_load(WORKFLOW.read_text())["jobs"]["check-and-update"]["steps"]
    if "run" in step
}
METADATA = "Get current and latest release metadata"
HEADERS = "Download Electron headers and compute checksum"
UPDATE = "Update PKGBUILD"
COMMIT = "a" * 40


class HermesUpdaterTest(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(shutil.which("jq"), "Install jq before running these tests")
        temporary = tempfile.TemporaryDirectory(dir=os.environ["TMPDIR"])
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.pkgbuild = self.work / "src/hermes-desktop/PKGBUILD"
        self.pkgbuild.parent.mkdir(parents=True)
        shutil.copyfile(REPO / "src/hermes-desktop/PKGBUILD", self.pkgbuild)
        self.current("0.21.5", "v2026.9.24")
        self.bin = self.work / "bin"
        self.bin.mkdir()
        curl = self.bin / "curl"
        curl.write_text(
            f"#!{sys.executable}\n"
            "import json, os, pathlib, sys\n"
            "args = sys.argv[1:]\n"
            "url = args[-1]\n"
            "fixtures = json.loads(pathlib.Path(os.environ['FIXTURES']).read_text())\n"
            "if url not in fixtures:\n"
            "    sys.exit('Unexpected fixture URL: ' + url)\n"
            "data = pathlib.Path(fixtures[url]).read_bytes()\n"
            "if '-fsSLo' in args:\n"
            "    pathlib.Path(args[args.index('-fsSLo') + 1]).write_bytes(data)\n"
            "else:\n"
            "    sys.stdout.buffer.write(data)\n"
        )
        curl.chmod(0o755)
        self.env = {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "TMPDIR": str(self.work),
            "RUNNER_TEMP": str(self.work),
            "GITHUB_OUTPUT": str(self.work / "output"),
            "GH_API_TOKEN": "fixture-only",
            "FIXTURES": str(self.work / "fixtures.json"),
            "LC_ALL": "C",
        }

    def fixture(self, tag="v0.21.7", version="0.0.0", package=None,
                root=None, missing=None):
        if package is None:
            package = {"devDependencies": {"electron": "44.9.3"}}
        root = root or f"hermes-agent-{tag.removeprefix('v')}"
        files = {
            "pyproject.toml": f'[project]\nversion = "{version}"\n'.encode(),
            "apps/desktop/package.json": json.dumps(package).encode(),
        }
        self.archive = self.work / "release.tar.gz"
        with self.archive.open("wb") as output:
            with gzip.GzipFile(fileobj=output, mode="wb", filename="", mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode="w") as archive:
                    for name, data in files.items():
                        if name == missing:
                            continue
                        info = tarfile.TarInfo(f"{root}/{name}")
                        info.size = len(data)
                        archive.addfile(info, io.BytesIO(data))
        responses = {
            "https://api.github.com/repos/NousResearch/hermes-agent/releases/latest":
                json.dumps({"tag_name": tag}).encode(),
            f"https://codeload.github.com/NousResearch/hermes-agent/tar.gz/refs/tags/{tag}":
                self.archive.read_bytes(),
            f"https://api.github.com/repos/NousResearch/hermes-agent/commits/{tag}":
                json.dumps({"sha": COMMIT}).encode(),
            "https://www.electronjs.org/headers/v44.9.3/node-v44.9.3-headers.tar.gz":
                b"deterministic Electron headers fixture\n",
        }
        fixtures = {}
        for index, (url, data) in enumerate(responses.items()):
            path = self.work / f"response-{index}"
            path.write_bytes(data)
            fixtures[url] = str(path)
        Path(self.env["FIXTURES"]).write_text(json.dumps(fixtures))

    def current(self, version, tag):
        text = self.pkgbuild.read_text()
        text = re.sub(r"^pkgver=.*$", f"pkgver={version}", text, flags=re.M)
        text = re.sub(r"^_tag=.*$", f"_tag='{tag}'", text, flags=re.M)
        self.pkgbuild.write_text(text)

    def run_step(self, name, **env):
        output = Path(self.env["GITHUB_OUTPUT"])
        output.write_text("")
        result = subprocess.run(
            ["bash", "-s"], input=STEPS[name], text=True, capture_output=True,
            cwd=self.work, env={**self.env, **env},
        )
        values = dict(line.split("=", 1) for line in output.read_text().splitlines())
        return result, values

    def metadata(self, latest, update):
        result, values = self.run_step(METADATA)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(values["latest"], latest)
        self.assertEqual(values["update_available"], update)
        self.assertEqual(values["electron_version"], "44.9.3")
        self.assertEqual(values["commit"], COMMIT)
        self.assertEqual(values["source_sha256"], hashlib.sha256(self.archive.read_bytes()).hexdigest())
        return values

    def test_modern_layout_and_tag_version(self):
        self.fixture()
        self.metadata("0.21.7", "true")

    def test_legacy_date_tag_and_electron_fallback(self):
        self.fixture(tag="v2026.9.25", version="0.21.6",
                     package={"build": {"electronVersion": "44.9.3"}})
        self.metadata("0.21.6", "true")

    def test_dev_dependency_takes_precedence(self):
        self.fixture(package={"devDependencies": {"electron": "44.9.3"},
                              "build": {"electronVersion": "39.0.0"}})
        self.metadata("0.21.7", "true")

    def test_already_current(self):
        self.current("0.21.7", "v0.21.7")
        self.fixture()
        self.metadata("0.21.7", "false")

    def test_downgrade_is_not_an_update(self):
        for tag, version in [("v0.21.7", "0.0.0"), ("v2026.9.25", "0.21.6")]:
            with self.subTest(tag=tag):
                self.current("0.21.8", "v0.21.8")
                self.fixture(tag=tag, version=version)
                self.metadata("0.21.7" if tag == "v0.21.7" else version, "false")

    def test_same_version_new_legacy_tag(self):
        self.fixture(tag="v2026.9.25", version="0.21.5")
        self.metadata("0.21.5", "true")

    def test_invalid_electron_has_clear_error(self):
        for electron in [None, "", "^40.10.2", "40.10", "invalid", 40, False]:
            with self.subTest(electron=electron):
                self.fixture(package={"devDependencies": {"electron": electron}})
                result, values = self.run_step(METADATA)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid upstream Electron version", result.stderr)
                self.assertEqual(values, {})

    def test_invalid_release_version_has_clear_error(self):
        for tag, version in [("v0.21.7-rc.1", "0.21.7"), ("latest", "0.21.7"),
                             ("v2026.9.25", "invalid"), ("v2026.9.25", "0.0.0")]:
            with self.subTest(tag=tag, version=version):
                self.fixture(tag=tag, version=version,
                             package={"build": {"electronVersion": "44.9.3"}})
                result, values = self.run_step(METADATA)
                self.assertNotEqual(result.returncode, 0)
                self.assertRegex(result.stderr, "Unsupported upstream tag|Upstream version")
                self.assertEqual(values, {})

    def test_archive_validation(self):
        for options, error in [({"root": "wrong-root"}, "Unexpected archive root"),
                               ({"missing": "apps/desktop/package.json"}, "Required file is missing"),
                               ({"missing": "pyproject.toml"}, "Required file is missing")]:
            with self.subTest(options=options):
                self.fixture(**options)
                result, values = self.run_step(METADATA)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(error, result.stderr)
                self.assertEqual(values, {})

    def test_electron_major_guard(self):
        result, values = self.run_step(HEADERS, ELECTRON_VERSION="45.0.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Electron major changed", result.stderr)
        self.assertEqual(values, {})

    def test_packaged_electron_is_consistent(self):
        pkgbuild = self.pkgbuild.read_text()
        electron_version = re.search(r"^_electronver='([^']+)'$", pkgbuild, re.M).group(1)
        electron_major = electron_version.split(".", 1)[0]
        self.assertIn(f"  'electron{electron_major}'\n", pkgbuild)
        self.assertIn(f"-c.electronDist=/usr/lib/electron{electron_major}\n", pkgbuild)
        launcher = (REPO / "src/hermes-desktop/hermes-desktop").read_text()
        self.assertRegex(launcher, rf"(?m)^exec electron{electron_major} ")

    def test_pkgbuild_update_and_checksums(self):
        self.fixture()
        original = self.pkgbuild.read_text().replace("pkgrel=1", "pkgrel=3")
        self.pkgbuild.write_text(original)
        metadata = self.metadata("0.21.7", "true")
        result, headers = self.run_step(HEADERS, ELECTRON_VERSION=metadata["electron_version"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(headers["sha256"], hashlib.sha256(
            b"deterministic Electron headers fixture\n").hexdigest())
        result, _ = self.run_step(UPDATE, LATEST=metadata["latest"], TAG=metadata["tag"],
                                 ELECTRON_VERSION=metadata["electron_version"], COMMIT=metadata["commit"],
                                 SOURCE_SHA256=metadata["source_sha256"], HEADERS_SHA256=headers["sha256"])
        self.assertEqual(result.returncode, 0, result.stderr)
        updated = self.pkgbuild.read_text()
        for line in ["pkgver=0.21.7", "pkgrel=1", "_tag='v0.21.7'",
                     "_electronver='44.9.3'", f"_commit='{COMMIT}'"]:
            self.assertIn(line + "\n", updated)
        hashes = re.findall(r"'([0-9a-f]{64})'", updated)
        self.assertEqual(hashes[:2], [metadata["source_sha256"], headers["sha256"]])
        self.assertEqual(hashes[2:], re.findall(r"'([0-9a-f]{64})'", original)[2:])


if __name__ == "__main__":
    unittest.main(verbosity=2)
