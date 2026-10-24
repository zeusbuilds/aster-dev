"""Offline subprocess tests for the actual CI helper; never use real credentials."""
import json
import os
from pathlib import Path
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[2] / "tool/configure_private_sdk_access.py"
GIT = shutil.which("git")
SSH = shutil.which("ssh")
FAKE_KEY = (
    "-----BEGIN OPENSSH PRIVATE KEY-----\n"
    "TEST_ONLY_NON_KEY_MATERIAL\n"
    "-----END OPENSSH PRIVATE KEY-----\n"
)


class PrivateSdkAccessTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="aster SDK CI test ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.runner = self.root / "runner temp"
        self.runner.mkdir()
        self.environment = self.root / "github-env"
        self.environment.touch()
        self.global_config = self.root / "original-gitconfig"
        self.global_config.write_text('[user]\n\tname = Preserved Fixture\n')
        self.bin = self.root / "bin"
        self.bin.mkdir()
        validator = self.bin / "ssh-keygen"
        validator.write_text(
            '#!/bin/sh\n'
            'test -z "${SDK_READ_SSH_KEY+x}" || exit 71\n'
            'test "$1" = -y && test "$2" = -P && test "$3" = "" '
            '&& test "$4" = -f && test -f "$5" || exit 72\n'
            'printf "%s\\n" "ssh-ed25519 TEST_ONLY_PUBLIC_VALIDATION_RESULT"\n'
        )
        validator.chmod(0o700)
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("GIT_CONFIG_") and key not in (
                        "SDK_CI_SSH_DIRECTORY", "SDK_READ_SSH_KEY", "GIT_SSH_COMMAND")}
        self.env.update({
            "GITHUB_ACTIONS": "true", "RUNNER_TEMP": str(self.runner),
            "GITHUB_ENV": str(self.environment), "SDK_READ_SSH_KEY": FAKE_KEY,
            "GIT_CONFIG_GLOBAL": str(self.global_config), "GIT_CONFIG_NOSYSTEM": "1",
            "PATH": str(self.bin) + os.pathsep + self.env["PATH"],
        })

    def run_helper(self, cleanup=False, env=None):
        result = subprocess.run(
            [sys.executable, "-I", "-S", str(HELPER), *(["--cleanup"] if cleanup else [])],
            env=self.env if env is None else env,
            capture_output=True, text=True, timeout=20,
        )
        self.assertNotIn("TEST_ONLY_NON_KEY_MATERIAL", result.stdout + result.stderr)
        return result

    def exported(self):
        result = {key: value for key, value in self.env.items() if key != "SDK_READ_SSH_KEY"}
        for line in self.environment.read_text().splitlines():
            name, value = line.split("=", 1)
            result[name] = value
        return result

    def configured(self):
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.exported()

    def test_private_files_strict_ssh_and_no_secret_export(self):
        env = self.configured()
        directory = Path(env["SDK_CI_SSH_DIRECTORY"])
        self.assertEqual(directory.parent, self.runner.resolve())
        self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
        self.assertEqual({p.name for p in directory.iterdir()}, {
            "id_ed25519", "known_hosts", "ssh_config", "state.json"})
        for path in directory.iterdir():
            self.assertFalse(path.is_symlink())
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertNotIn("SDK_READ_SSH_KEY", self.environment.read_text())
        self.assertNotIn("TEST_ONLY_NON_KEY_MATERIAL", self.environment.read_text())
        self.assertEqual((directory / "id_ed25519").read_text(), FAKE_KEY)
        config = subprocess.check_output(
            [SSH, "-G", "-F", str(directory / "ssh_config"), "aster-sdk-read"],
            env=env, text=True, stderr=subprocess.DEVNULL,
        )
        for setting in ["hostname github.com", "hostkeyalias github.com",
                        "hostkeyalgorithms ssh-ed25519", "stricthostkeychecking true",
                        "identityagent none", "identitiesonly yes", "batchmode yes",
                        "passwordauthentication no", "kbdinteractiveauthentication no"]:
            self.assertIn(setting, config)
        self.assertEqual(shlex.split(env["GIT_CONFIG_VALUE_1"]),
                         ["ssh", "-F", str(directory / "ssh_config")])

    def test_git_rewrites_only_sdk_remote_and_preserves_host_configuration(self):
        before = self.global_config.read_bytes()
        env = self.configured()
        urls = {
            "https://github.com/zeusbuilds/rgb-sdk-flutter.git":
                "ssh://git@aster-sdk-read/zeusbuilds/rgb-sdk-flutter.git",
            "https://github.com/UTEXO-Protocol/flutter-sdk.git":
                "https://github.com/UTEXO-Protocol/flutter-sdk.git",
            "https://github.com/zeusbuilds/another-repository.git":
                "https://github.com/zeusbuilds/another-repository.git",
        }
        for source, expected in urls.items():
            actual = subprocess.check_output(
                [GIT, "ls-remote", "--get-url", source], env=env, text=True).strip()
            self.assertEqual(actual, expected)
        self.assertEqual(self.global_config.read_bytes(), before)

    def test_cleanup_restores_existing_git_entries_and_removes_credential_files(self):
        self.env.update({"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "user.name",
                         "GIT_CONFIG_VALUE_0": "Existing Environment Fixture"})
        env = self.configured()
        directory = Path(env["SDK_CI_SSH_DIRECTORY"])
        self.assertEqual(env["GIT_CONFIG_COUNT"], "3")
        result = self.run_helper(cleanup=True, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(directory.exists())
        env = self.exported()
        self.assertEqual(env["GIT_CONFIG_COUNT"], "1")
        self.assertEqual(subprocess.check_output(
            [GIT, "config", "user.name"], env=env, text=True).strip(),
            "Existing Environment Fixture")
        self.assertEqual(env["SDK_CI_SSH_DIRECTORY"], "")

    def test_missing_secret_creates_no_files_or_environment_entries(self):
        del self.env["SDK_READ_SSH_KEY"]
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.runner.iterdir()), [])
        self.assertEqual(self.environment.read_text(), "")

    def test_invalid_key_validator_failure_does_not_expose_or_retain_key(self):
        (self.bin / "ssh-keygen").write_text('#!/bin/sh\nprintf "PRIVATE_DIAGNOSTIC" >&2\nexit 1\n')
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("PRIVATE_DIAGNOSTIC", result.stdout + result.stderr)
        self.assertEqual(list(self.runner.iterdir()), [])
        self.assertEqual(self.environment.read_text(), "")

    def test_non_actions_and_symlinked_environment_are_rejected(self):
        self.env["GITHUB_ACTIONS"] = "false"
        self.assertNotEqual(self.run_helper().returncode, 0)
        self.env["GITHUB_ACTIONS"] = "true"
        target = self.root / "untouched"
        target.write_text("preserve")
        self.environment.unlink()
        self.environment.symlink_to(target)
        self.assertNotEqual(self.run_helper().returncode, 0)
        self.assertEqual(target.read_text(), "preserve")
        self.assertEqual(list(self.runner.iterdir()), [])

    def test_cleanup_refuses_a_directory_outside_runner_temp(self):
        directory = self.root / "aster-sdk-read-unowned"
        directory.mkdir(mode=0o700)
        marker = directory / "state.json"
        marker.write_text(json.dumps({"base_config_count": 0}))
        self.env["SDK_CI_SSH_DIRECTORY"] = str(directory)
        self.assertNotEqual(self.run_helper(cleanup=True).returncode, 0)
        self.assertTrue(marker.exists())

    def test_cleanup_without_setup_is_a_safe_noop(self):
        self.assertEqual(self.run_helper(cleanup=True).returncode, 0)
        self.assertEqual(self.environment.read_text(), "")


if __name__ == "__main__":
    unittest.main()
