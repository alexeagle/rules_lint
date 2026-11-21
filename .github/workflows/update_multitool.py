"""Update GitHub release binaries using authenticated gh API requests.

Multitool v0.9.0 does not support authenticated release lookups and panics on
GitHub's anonymous API rate limit. Keep this updater here until upstream supports
authentication and actionable errors for missing release assets.
"""

import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

RELEASE_URL = re.compile(
    r"https://github\.com/(?P<repo>[^/]+/[^/]+)/releases/download/"
    r"(?P<tag>[^/]+)/(?P<asset>.+)"
)


def release_info(repo):
    result = subprocess.run(
        ["gh", "api", f"repos/{repo}/releases/latest"],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    release = json.loads(result.stdout)
    if not isinstance(release.get("tag_name"), str) or not release["tag_name"]:
        raise ValueError(f"{repo}: latest release has no tag_name")
    return release


def checksum(asset):
    # Stream through a temporary file rather than holding large archives in RAM.
    with tempfile.TemporaryFile() as download:
        subprocess.run(
            ["gh", "api", "-H", "Accept: application/octet-stream", asset["url"]],
            stdout=download,
            check=True,
        )
        download.seek(0)
        digest = hashlib.file_digest(download, "sha256").hexdigest()
    expected = asset.get("digest")
    if expected and expected != f"sha256:{digest}":
        raise ValueError(f"Checksum mismatch for {asset['name']}")
    return digest


def update(lockfile, releases, checksums):
    for tool, definition in lockfile.items():
        if tool == "$schema":
            continue
        for binary in definition["binaries"]:
            match = RELEASE_URL.fullmatch(binary["url"])
            if not match:
                continue
            repo, old_tag, old_name = match.group("repo", "tag", "asset")
            if repo not in releases:
                releases[repo] = release_info(repo)
            release = releases[repo]
            tag = release["tag_name"]
            if old_tag == tag:
                continue
            old_version, version = old_tag.removeprefix("v"), tag.removeprefix("v")
            name = old_name.replace(old_version, version)
            assets = {asset["name"]: asset for asset in release["assets"]}
            if name not in assets:
                raise ValueError(f"{tool}: {repo} {tag} has no asset {name}")
            asset = assets[name]
            url = asset["browser_download_url"]
            if url not in checksums:
                checksums[url] = checksum(asset)
            binary["url"] = url
            binary["sha256"] = checksums[url]
            if "file" in binary:
                binary["file"] = binary["file"].replace(old_version, version)
            print(f"Updating {tool} ({binary['os']}/{binary['cpu']}): {old_tag} -> {tag}")
    return lockfile


def main(paths):
    releases, checksums, pending = {}, {}, {}
    # Validate every update before writing either lockfile.
    for name in paths:
        path = Path(name)
        pending[path] = update(json.loads(path.read_text()), releases, checksums)
    for path, lockfile in pending.items():
        path.write_text(json.dumps(lockfile, indent=2) + "\n")


if __name__ == "__main__":
    main(sys.argv[1:])
