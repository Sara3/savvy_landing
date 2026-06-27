#!/usr/bin/env python3
"""Classify a gate check's outcome from its exit code. Prints ONE token: CLEAN | FINDINGS | INFRA.

This is the heart of the Type-C contract: distinguish "found a problem" (the check
RAN and produced a real, code-attributable finding) from "couldn't run" (the check
crashed, OOM'd, timed out, or hit an environment/setup error unrelated to the PR).

  CLEAN    — exit 0. The check ran and passed.
  FINDINGS — the check ran and found a real problem in the PR (Type A/B).
             Only this outcome may be handed to the auto-fixer or read as a code FAIL.
  INFRA    — the check could NOT run to a trustworthy conclusion (Type C).
             Must be retried; if persistent, escalated as an INFRA signal and routed
             to a human as "couldn't verify" — NEVER fed to the fixer, NEVER auto-passed.

Decision tree (first match wins):
  1. rc == 0                      -> CLEAN
  2. rc > 128 (killed by signal)  -> INFRA   (137 OOM-kill, 134 abort, 139 segv,
                                              143 SIGTERM = step/job timeout cancel)
  3. rc in findings-codes:
       - output empty             -> INFRA   (a "findings" exit code with no findings
                                              text smells like a crash, not a real hit)
       - output non-empty         -> FINDINGS
  4. any other non-zero rc        -> INFRA   (unexpected error code = the tool errored,
                                              e.g. semgrep exit 2, npm ci registry fail)

Exit-code conventions per tool (passed via --findings-codes):
  semgrep --error      : 1 = findings        (>=2 = crash/config error -> INFRA)
  tsc --noEmit         : 1,2 = type errors   (137/134 = OOM -> INFRA)
  vitest/jest          : 1 = test failures
  npm ci / pip install : <none>              (any non-zero = setup/INFRA failure)
  squawk               : handled in-line (ban-drop grep) — see gate.yml
"""
import argparse
import sys


def classify(rc: int, findings_codes: set[int], output_empty: bool) -> str:
    if rc == 0:
        return "CLEAN"
    # Signals (rc = 128 + signum): OOM-kill (137), abort (134), segfault (139),
    # SIGTERM from a step/job timeout cancel (143). Always an infra/environment crash.
    if rc > 128:
        return "INFRA"
    if rc in findings_codes:
        # A findings exit code with no output is not a trustworthy finding — the tool
        # likely died after setting the code. Treat defensively as a crash.
        return "INFRA" if output_empty else "FINDINGS"
    # Any other non-zero code is an unexpected tool error, not a code finding.
    return "INFRA"


def _parse_codes(raw: str) -> set[int]:
    out: set[int] = set()
    for part in (raw or "").split(","):
        part = part.strip()
        if part:
            out.add(int(part))
    return out


# ---------------------------------------------------------------------------
# Self-test (no external dependency)
# ---------------------------------------------------------------------------
SELFTEST_CASES = [
    # (desc, rc, findings_codes, output_empty, expected)
    ("clean pass",                       0, {1},    False, "CLEAN"),
    ("semgrep real finding",             1, {1},    False, "FINDINGS"),
    ("semgrep crash (exit 2)",           2, {1},    False, "INFRA"),
    ("OOM kill (137)",                   137, {1, 2}, False, "INFRA"),
    ("abort (134)",                      134, {1, 2}, True,  "INFRA"),
    ("step/job timeout SIGTERM (143)",   143, {1},   True,  "INFRA"),
    ("npm ci failure (no findings codes)", 1, set(), False, "INFRA"),
    ("tsc type error",                   2, {1, 2}, False, "FINDINGS"),
    ("findings code but empty output",   1, {1},    True,  "INFRA"),
    ("unexpected exit 3",                3, {1},    False, "INFRA"),
]


def run_selftest() -> int:
    ok = True
    for desc, rc, codes, empty, expected in SELFTEST_CASES:
        got = classify(rc, codes, empty)
        passed = got == expected
        ok = ok and passed
        print(f"  [{'PASS' if passed else 'FAIL'}] {desc}: rc={rc} codes={sorted(codes)} "
              f"empty={empty} -> {got} (expected {expected})")
    print("SELFTEST PASS" if ok else "SELFTEST FAIL")
    return 0 if ok else 1


def main() -> None:
    ap = argparse.ArgumentParser(description="Classify a gate check outcome by exit code.")
    ap.add_argument("--rc", type=int, help="exit code of the check command")
    ap.add_argument("--findings-codes", default="",
                    help="comma-separated exit codes that mean a real finding (e.g. '1' or '1,2')")
    ap.add_argument("--output-empty", action="store_true",
                    help="set when the check produced no stdout/stderr (defensive crash signal)")
    ap.add_argument("--selftest", action="store_true", help="run built-in tests and exit")
    args = ap.parse_args()

    if args.selftest:
        sys.exit(run_selftest())

    if args.rc is None:
        ap.error("--rc is required (or use --selftest)")

    print(classify(args.rc, _parse_codes(args.findings_codes), args.output_empty))


if __name__ == "__main__":
    main()
