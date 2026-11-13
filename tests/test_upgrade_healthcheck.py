import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def replace_exact(text: str, old: str, new: str) -> str:
    if old not in text:
        raise AssertionError(f"Expected pattern {old!r} not found in script")
    return text.replace(old, new)


def re_sub_exact(pattern: str, repl: str, text: str) -> str:
    new_text, count = re.subn(pattern, repl, text)
    if count == 0:
        raise AssertionError(f"Pattern {pattern!r} did not match in script")
    return new_text


class UpgradeHealthcheckTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        post_result = subprocess.run(
            ["nix", "build", "--no-link", "--print-out-paths", "--impure", "--expr",
             'builtins.elemAt ((builtins.getFlake (toString ./nix)).nixosConfigurations.lm-server.config.systemd.services.nixos-upgrade.serviceConfig.ExecStopPost) 0'],
            cwd=ROOT, check=True, capture_output=True, text=True,
        )
        cls.script = Path(post_result.stdout.strip()).read_text()

        pre_result = subprocess.run(
            ["nix", "build", "--no-link", "--print-out-paths", "--impure", "--expr",
             'builtins.elemAt ((builtins.getFlake (toString ./nix)).nixosConfigurations.lm-server.config.systemd.services.nixos-upgrade.serviceConfig.ExecStartPre) 0'],
            cwd=ROOT, check=True, capture_output=True, text=True,
        )
        cls.pre_script = Path(pre_result.stdout.strip()).read_text()

    def run_check(self, *, state="starting", jobs="452 nixos-upgrade.service start running",
                  failed="", required=True, previous="same", service_result="success",
                  jobs_exit=0, units_exit=0, jobs_after_first=None, timeout_sec=0,
                  rollback_exit=0, current_missing=False):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "bootstrapped").touch()
            (tmp / "system-3-link").symlink_to(tmp / "current")
            (tmp / "system").symlink_to("system-3-link")
            if not current_missing:
                (tmp / "current").touch()
            if previous != "unknown":
                (tmp / "pre").write_text(str(tmp / ("current" if previous == "same" else "old")))
            fake = tmp / "systemctl"
            fake.write_text('''#!/bin/sh
case "$1" in
  is-system-running) printf '%s\\n' "$TEST_STATE" ;;
  list-units)
    if [ "${TEST_UNITS_EXIT:-0}" != "0" ]; then exit "$TEST_UNITS_EXIT"; fi
    printf '%s' "$TEST_FAILED"
    ;;
  list-jobs)
    if [ "${TEST_JOBS_EXIT:-0}" != "0" ]; then exit "$TEST_JOBS_EXIT"; fi
    if [ -e "$TEST_JOBS_QUERIED" ] && [ "${TEST_JOBS_AFTER_FIRST+x}" = x ]; then
      printf '%s\\n' "$TEST_JOBS_AFTER_FIRST"
      exit 0
    fi
    touch "$TEST_JOBS_QUERIED"
    printf '%s\\n' "$TEST_JOBS"
    ;;
  is-active) test "$TEST_REQUIRED" = true ;;
esac
''')
            fake.chmod(0o755)
            rollback = tmp / "rollback"
            rollback.write_text('#!/bin/sh\ntouch "' + str(tmp / "rolled-back") + '"\nexit "$TEST_ROLLBACK_EXIT"\n')
            rollback.chmod(0o755)
            script = self.script
            script = re_sub_exact(r'/nix/store/[^ /]+/bin/systemctl', str(fake), script)
            script = re_sub_exact(r'/nix/store/[^ /]+/bin/nixos-rebuild', str(rollback), script)
            for old, new in {
                "/var/lib/bootstrap-second-switch-done": tmp / "absent",
                "/var/lib/nixos-bootstrap-done": tmp / "bootstrapped",
                "/run/nixos-upgrade/pre-upgrade-profile": tmp / "pre",
                "/nix/var/nix/profiles/system": tmp / "system",
                "/var/log/nixos-rollback.log": tmp / "log",
                "/var/lib/prometheus/node-exporter": tmp / "no-metrics",
            }.items():
                script = replace_exact(script, old, str(new))
                self.assertNotIn(old, script)
            script = replace_exact(script, "sleep 5", "sleep 0")
            script = replace_exact(script, "sleep 3", "sleep 0.01")
            script = replace_exact(script, "+ 90 ))", f"+ {timeout_sec} ))")
            self.assertNotIn("sleep 5", script)
            self.assertNotIn("+ 90 ))", script)
            env = dict(os.environ, TEST_STATE=state, TEST_JOBS=jobs, TEST_FAILED=failed,
                       TEST_REQUIRED=str(required).lower(), SERVICE_RESULT=service_result,
                       TEST_JOBS_EXIT=str(jobs_exit), TEST_UNITS_EXIT=str(units_exit),
                       TEST_JOBS_QUERIED=str(tmp / "jobs-queried"),
                       TEST_ROLLBACK_EXIT=str(rollback_exit))
            env.pop("TEST_JOBS_AFTER_FIRST", None)
            if jobs_after_first is not None:
                env["TEST_JOBS_AFTER_FIRST"] = jobs_after_first
            result = subprocess.run(["bash"], input=script, env=env, text=True,
                                    capture_output=True, timeout=10)
            return result, (tmp / "rolled-back").exists()

    def test_pre_check_records_current_profile_and_removes_old_record(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            run_dir = tmp / "run"
            run_dir.mkdir(parents=True)
            pre_file = run_dir / "pre-upgrade-profile"
            pre_file.write_text("/stale/old/profile")

            target_gen = tmp / "system-5-link"
            target_gen.touch()
            system_link = tmp / "system"
            system_link.symlink_to(target_gen)

            script = self.pre_script
            script = replace_exact(script, "/run/nixos-upgrade", str(run_dir))
            script = replace_exact(script, "/nix/var/nix/profiles/system", str(system_link))

            result = subprocess.run(["bash"], input=script, text=True, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(pre_file.read_text().strip(), str(target_gen.resolve()))

    def test_pre_check_fails_when_profile_missing(self):
        for missing in ("parent", "link", "target"):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as tmp:
                tmp = Path(tmp)
                run_dir = tmp / "run"
                missing_system = tmp / "system"
                if missing == "parent":
                    missing_system = tmp / "nonexistent-dir" / "system"
                elif missing == "target":
                    missing_system.symlink_to(tmp / "missing-target")

                script = self.pre_script
                script = replace_exact(script, "/run/nixos-upgrade", str(run_dir))
                script = replace_exact(script, "/nix/var/nix/profiles/system", str(missing_system))

                result = subprocess.run(["bash"], input=script, text=True, capture_output=True, timeout=5)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((run_dir / "pre-upgrade-profile").read_text(), "")

    def test_starting_with_only_upgrade_job_succeeds(self):
        result, rolled_back = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(rolled_back)

    def test_other_startup_job_does_not_pass(self):
        result, _ = self.run_check(jobs="452 nixos-upgrade.service start running\n453 other.service start waiting")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Healthcheck failed within", result.stderr)
        self.assertIn("other.service", result.stderr)

    def test_starting_without_upgrade_job_does_not_pass(self):
        result, _ = self.run_check(jobs="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Healthcheck failed within", result.stderr)

    def test_other_startup_job_finishes_while_waiting(self):
        result, rolled_back = self.run_check(
            jobs="452 nixos-upgrade.service start running\n453 other.service start waiting",
            jobs_after_first="452 nixos-upgrade.service start running",
            timeout_sec=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Healthcheck passed", result.stdout)
        self.assertFalse(rolled_back)

    def test_failed_or_required_unit_does_not_pass(self):
        for kwargs in ({"failed": "broken.service"}, {"required": False}):
            with self.subTest(**kwargs):
                result, _ = self.run_check(**kwargs)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Healthcheck failed within", result.stderr)

    def test_jobs_query_failure_does_not_pass(self):
        result, _ = self.run_check(state="running", jobs_exit=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Healthcheck failed within", result.stderr)
        self.assertIn("pending_jobs=[failed to retrieve]", result.stderr)

    def test_units_query_failure_does_not_pass(self):
        result, _ = self.run_check(state="running", units_exit=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Healthcheck failed within", result.stderr)
        self.assertIn("failed_units=[failed to retrieve]", result.stderr)

    def test_missing_current_profile_is_not_treated_as_unchanged(self):
        result, rolled_back = self.run_check(current_missing=True, required=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("previous profile is unknown", result.stderr)
        self.assertFalse(rolled_back)

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
        self.assertIn("Healthcheck failed within", result.stderr)
        self.assertTrue(rolled_back)

    def test_changed_profile_rolls_back_on_main_process_failure(self):
        result, rolled_back = self.run_check(previous="changed", service_result="exit-code")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("main process failed after switching profile", result.stderr)
        self.assertTrue(rolled_back)
        self.assertIn("SUCCESS: Rolled back", result.stdout)

    def test_rollback_failure_is_reported(self):
        for service_result in ("success", "exit-code"):
            with self.subTest(service_result=service_result):
                result, rolled_back = self.run_check(
                    previous="changed", required=False, service_result=service_result,
                    rollback_exit=1,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(rolled_back)
                self.assertIn("CRITICAL: nixos-rebuild switch --rollback failed!", result.stderr)
                self.assertNotIn("SUCCESS: Rolled back", result.stdout)


if __name__ == "__main__":
    unittest.main()
