#!/usr/bin/env python3
"""Unit tests for the pure timer/checkpoint policy shared with QML.

timer-policy.js is imported by Service.qml and PomodoroView.qml, and required
directly here, so these tests exercise the same decisions the running shell
makes without needing a QML visual tree. In particular they cover the Reset
race: a full-duration phase after Reset must not be mistaken for progress.
"""

import json
import os
import shutil
import subprocess
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POLICY = os.path.join(ROOT, "timer-policy.js")

NODE_HARNESS = r"""
// With `node -e`, process.argv[1] is the first argument after the script.
const policy = require(process.argv[1]);
const fn = process.argv[2];
const args = JSON.parse(process.argv[3]);
process.stdout.write(JSON.stringify(policy[fn].apply(null, args)));
"""


def call_policy(name, *args):
    if shutil.which("node") is None:
        raise unittest.SkipTest("node is needed to exercise timer-policy.js")
    proc = subprocess.run(
        ["node", "-e", NODE_HARNESS, POLICY, name, json.dumps(list(args))],
        text=True, capture_output=True, timeout=15)
    if proc.returncode != 0:
        raise AssertionError("policy call failed: " + proc.stderr)
    return json.loads(proc.stdout)


class TimerPolicyTest(unittest.TestCase):
    def test_reset_while_running_is_detected_from_a_full_phase(self):
        self.assertTrue(call_policy("resetWhileRunning", True, False, 1500, 25))

    def test_pause_keeps_a_partially_elapsed_phase(self):
        self.assertFalse(call_policy("resetWhileRunning", True, False, 1200, 25))

    def test_reset_while_already_paused_needs_no_suppression(self):
        self.assertFalse(call_policy("resetWhileRunning", False, False, 1500, 25))

    def test_a_still_running_phase_is_not_a_reset(self):
        self.assertFalse(call_policy("resetWhileRunning", True, True, 1500, 25))

    def test_restored_long_break_is_partially_elapsed(self):
        self.assertTrue(call_policy("isPartiallyElapsed", "longBreak", 600, 25, 5, 30))

    def test_fresh_long_break_is_not_partially_elapsed(self):
        self.assertFalse(call_policy("isPartiallyElapsed", "longBreak", 1800, 25, 5, 30))

    def test_fresh_focus_session_is_not_partially_elapsed(self):
        self.assertFalse(call_policy("isPartiallyElapsed", "focus", 1500, 25, 5, 30))

    def test_halted_cycle_has_no_partially_elapsed_phase(self):
        self.assertFalse(call_policy("isPartiallyElapsed", "cycleComplete", 0, 25, 5, 30))


if __name__ == "__main__":
    unittest.main()
