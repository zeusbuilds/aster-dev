#!/usr/bin/env python3
"""Configure one read-only private SDK dependency, without global Git changes.

The deploy key is supplied only to this setup step. Git receives configuration
paths through GITHUB_ENV; the immediately following cleanup step removes the key.
No network host-key discovery or credential-bearing URL is used.
"""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile

SDK_URL = "https://github.com/zeusbuilds/rgb-sdk-flutter.git"
SSH_URL = "ssh://git@aster-sdk-read/zeusbuilds/rgb-sdk-flutter.git"
# https://api.github.com/meta, verified 2026-10-24. GitHub's ED25519 fingerprint:
# SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU
GITHUB_HOST_KEY = (
    "github.com ssh-ed25519 "
    "AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl\n"
)
PREFIX = "aster-sdk-read-"
FILES = {"id_ed25519", "known_hosts", "ssh_config", "state.json"}


class SetupError(Exception):
    """A concise failure that never includes credential material."""


def runner_paths():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise SetupError("Private SDK access is restricted to GitHub Actions.")
    values = [os.environ.get(name, "") for name in ("RUNNER_TEMP", "GITHUB_ENV")]
    if any(not value or "\n" in value or "\r" in value for value in values):
        raise SetupError("GitHub Actions runner paths are unavailable.")
    temporary, environment = (Path(value) for value in values)
    if temporary.is_symlink() or not temporary.is_dir():
        raise SetupError("Runner temporary storage is unavailable.")
    if environment.is_symlink() or not environment.is_file():
        raise SetupError("GitHub Actions environment file is unavailable.")
    return temporary.resolve(), environment


def private_file(path, text):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    with os.fdopen(os.open(path, flags, 0o600), "w") as file:
        file.write(text)


def export_environment(path, values):
    if any("\n" in value or "\r" in value for value in values.values()):
        raise SetupError("SDK configuration paths must contain one line.")
    flags = os.O_WRONLY | os.O_APPEND | getattr(os, "O_NOFOLLOW", 0)
    with os.fdopen(os.open(path, flags), "a") as file:
        if not stat.S_ISREG(os.fstat(file.fileno()).st_mode):
            raise SetupError("GitHub Actions environment file is unavailable.")
        file.write("".join(f"{name}={value}\n" for name, value in values.items()))


def ssh_path(path):
    return '"' + str(path).replace("\\", "\\\\").replace('"', '\\"') + '"'


def remove_owned_files(directory):
    for name in FILES:
        path = directory / name
        if path.exists() or path.is_symlink():
            path.unlink()
    directory.rmdir()


def configure():
    temporary, environment = runner_paths()
    if os.environ.get("SDK_CI_SSH_DIRECTORY"):
        raise SetupError("Clean up the previous SDK access configuration first.")
    key = os.environ.pop("SDK_READ_SSH_KEY", "")
    if not key:
        raise SetupError("SDK_READ_SSH_KEY is unavailable; configure the read-only SDK deploy key.")
    if (len(key) > 32768 or "\x00" in key
            or not key.startswith("-----BEGIN OPENSSH PRIVATE KEY-----")
            or not key.rstrip().endswith("-----END OPENSSH PRIVATE KEY-----")):
        raise SetupError("The SDK deploy key is not a supported OpenSSH key.")
    count_text = os.environ.get("GIT_CONFIG_COUNT", "0")
    if not count_text.isdecimal() or not 0 <= int(count_text) <= 256:
        raise SetupError("Existing Git environment configuration is invalid.")
    count = int(count_text)
    for index in range(count):
        if any(f"GIT_CONFIG_{kind}_{index}" not in os.environ for kind in ("KEY", "VALUE")):
            raise SetupError("Existing Git environment configuration is incomplete.")
    directory = Path(tempfile.mkdtemp(prefix=PREFIX, dir=temporary))
    try:
        directory.chmod(0o700)
        identity = directory / "id_ed25519"
        private_file(identity, key.rstrip() + "\n")
        key = ""
        executable = shutil.which("ssh-keygen")
        if executable is None:
            raise SetupError("OpenSSH key validation is unavailable.")
        checked = subprocess.run(
            [executable, "-y", "-P", "", "-f", str(identity)],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, timeout=15, check=False,
        )
        if checked.returncode or not checked.stdout.startswith(b"ssh-ed25519 "):
            raise SetupError("The SDK deploy key must be an unencrypted ED25519 key.")
        private_file(directory / "known_hosts", GITHUB_HOST_KEY)
        config = directory / "ssh_config"
        private_file(config, "\n".join([
            "Host aster-sdk-read", "  HostName github.com", "  User git",
            "  HostKeyAlias github.com", "  HostKeyAlgorithms ssh-ed25519",
            "  StrictHostKeyChecking yes",
            "  UserKnownHostsFile " + ssh_path(directory / "known_hosts"),
            "  GlobalKnownHostsFile /dev/null",
            "  IdentityFile " + ssh_path(identity), "  IdentityAgent none",
            "  IdentitiesOnly yes", "  BatchMode yes",
            "  PasswordAuthentication no", "  KbdInteractiveAuthentication no",
            "  LogLevel ERROR", "",
        ]))
        private_file(directory / "state.json", json.dumps({"base_config_count": count}))
        export_environment(environment, {
            "SDK_CI_SSH_DIRECTORY": str(directory),
            f"GIT_CONFIG_KEY_{count}": f"url.{SSH_URL}.insteadOf",
            f"GIT_CONFIG_VALUE_{count}": SDK_URL,
            f"GIT_CONFIG_KEY_{count + 1}": "core.sshCommand",
            f"GIT_CONFIG_VALUE_{count + 1}": "ssh -F " + shlex.quote(str(config)),
            "GIT_CONFIG_COUNT": str(count + 2),
        })
    except BaseException:
        remove_owned_files(directory)
        raise
    print("Read-only SDK dependency access configured.")


def cleanup():
    temporary, environment = runner_paths()
    value = os.environ.get("SDK_CI_SSH_DIRECTORY", "")
    if not value:
        return
    directory = Path(value)
    if (directory.is_symlink() or directory.parent != temporary
            or not directory.name.startswith(PREFIX) or not directory.is_dir()
            or stat.S_IMODE(directory.stat().st_mode) != 0o700
            or directory.stat().st_uid != os.getuid()):
        raise SetupError("Refusing an unowned SDK credential directory.")
    state = directory / "state.json"
    if state.is_symlink() or not state.is_file():
        raise SetupError("SDK access cleanup state is unavailable.")
    saved = json.loads(state.read_text())
    count = saved.get("base_config_count")
    if type(count) is not int or not 0 <= count <= 256:
        raise SetupError("SDK access cleanup state is invalid.")
    export_environment(environment, {
        "GIT_CONFIG_COUNT": str(count),
        f"GIT_CONFIG_KEY_{count}": "", f"GIT_CONFIG_VALUE_{count}": "",
        f"GIT_CONFIG_KEY_{count + 1}": "", f"GIT_CONFIG_VALUE_{count + 1}": "",
        "SDK_CI_SSH_DIRECTORY": "",
    })
    remove_owned_files(directory)
    print("Read-only SDK dependency credentials removed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cleanup", action="store_true")
    args = parser.parse_args()
    try:
        cleanup() if args.cleanup else configure()
    except SetupError as error:
        print(str(error), file=sys.stderr)
        return 1
    except Exception:
        print("SDK dependency access setup/cleanup failed.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
