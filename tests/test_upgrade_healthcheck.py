import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class UpgradeHealthcheckTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            ["nix", "build", "--no-link", "--print-out-paths", "--impure", "--expr",
             'builtins.elemAt ((builtins.getFlake (toString ./nix)).nixosConfigurations.lm-server.config.systemd.services.nixos-upgrade.serviceConfig.ExecStopPost) 0'],
            cwd=ROOT, check=True, capture_output=True, text=True,
        )
        cls.script = Path(result.stdout.strip()).read_text()

    def run_check(self, *, state="starting", jobs="452 nixos-upgrade.service start running",
                  failed="", required=True, previous="same", service_result="success"):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "bootstrapped").touch()
            (tmp / "system-3-link").symlink_to(tmp / "current")
            (tmp / "system").symlink_to("system-3-link")
            (tmp / "current").touch()
            if previous != "unknown":
                (tmp / "pre").write_text(str(tmp / ("current" if previous == "same" else "old")))
            fake = tmp / "systemctl"
            fake.write_text('''#!/bin/sh
case "$1" in
  is-system-running) printf '%s\\n' "$TEST_STATE" ;;
  list-units) printf '%s' "$TEST_FAILED" ;;
  list-jobs) printf '%s\\n' "$TEST_JOBS" ;;
  is-active) test "$TEST_REQUIRED" = true ;;
esac
''')
            fake.chmod(0o755)
            rollback = tmp / "rollback"
            rollback.write_text('#!/bin/sh\ntouch "' + str(tmp / "rolled-back") + '"\n')
            rollback.chmod(0o755)
            script = self.script
            script = re.sub(r'/nix/store/[^ /]+/bin/systemctl', str(fake), script)
            script = re.sub(r'/nix/store/[^ /]+/bin/nixos-rebuild', str(rollback), script)
            for old, new in {
                "/var/lib/bootstrap-second-switch-done": tmp / "absent",
                "/var/lib/nixos-bootstrap-done": tmp / "bootstrapped",
                "/run/nixos-upgrade/pre-upgrade-profile": tmp / "pre",
                "/nix/var/nix/profiles/system": tmp / "system",
                "/var/log/nixos-rollback.log": tmp / "log",
                "/var/lib/prometheus/node-exporter": tmp / "no-metrics",
            }.items():
                script = script.replace(old, str(new))
            script = script.replace("sleep 5", "sleep 0").replace("sleep 3", "sleep 0.01")
            script = script.replace("+ 90 ))", "+ 0 ))")
            env = dict(os.environ, TEST_STATE=state, TEST_JOBS=jobs, TEST_FAILED=failed,
                       TEST_REQUIRED=str(required).lower(), SERVICE_RESULT=service_result)
            result = subprocess.run(["bash"], input=script, env=env, text=True,
                                    capture_output=True, timeout=10)
            return result, (tmp / "rolled-back").exists()

    def test_starting_with_only_upgrade_job_succeeds(self):
        result, rolled_back = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(rolled_back)

    def test_other_startup_job_does_not_pass(self):
        result, _ = self.run_check(jobs="452 nixos-upgrade.service start running\n453 other.service start waiting")
        self.assertNotEqual(result.returncode, 0)

    def test_starting_without_upgrade_job_does_not_pass(self):
        result, _ = self.run_check(jobs="")
        self.assertNotEqual(result.returncode, 0)

    def test_failed_or_required_unit_does_not_pass(self):
        for kwargs in ({"failed": "broken.service"}, {"required": False}):
            with self.subTest(**kwargs):
                result, _ = self.run_check(**kwargs)
                self.assertNotEqual(result.returncode, 0)

    def test_unknown_previous_profile_is_not_treated_as_unchanged(self):
        result, rolled_back = self.run_check(previous="unknown", required=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("previous profile is unknown", result.stderr)
        self.assertFalse(rolled_back)

    def test_failed_upgrade_with_unknown_profile_is_reported(self):
        result, rolled_back = self.run_check(previous="unknown", service_result="exit-code")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("previous profile is unknown", result.stderr)
        self.assertFalse(rolled_back)

    def test_changed_profile_rolls_back_on_health_failure(self):
        result, rolled_back = self.run_check(previous="changed", required=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(rolled_back)


if __name__ == "__main__":
    unittest.main()
