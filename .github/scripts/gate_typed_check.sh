#!/usr/bin/env bash
# gate_typed_check.sh — run a gate check, classify findings-vs-infra, retry
# transient infra failures, and escalate persistent ones. The single DRY entry
# point that makes db-squawk's discipline universal across every deterministic check.
#
# It enforces the Type-C contract for the wrapped command:
#   - FINDINGS (the check ran, real hit): exit 1, infra_error=false  -> a code FAIL,
#     eligible to be handed to the auto-fixer.
#   - INFRA (couldn't run): RETRY up to --retries times; if still INFRA, call
#     gate_infra_escalate.sh and exit 1 with infra_error=true  -> NEVER fed to the
#     fixer, NEVER auto-passed, human-visible infra escalation.
#   - CLEAN: exit 0, infra_error=false.
#
# Emits to $GITHUB_OUTPUT (when set):
#   outcome=clean|findings|infra
#   infra_error=true|false
# so the job can surface `infra_error` as a job output and the Sonnet floor_check
# can exclude infra failures from the "safe failures to fix" list.
#
# Usage:
#   gate_typed_check.sh --name <check> --findings-codes "1[,2]" [--retries 2] \
#       [--retry-sleep 5] [--pr <num>] -- <command> [args...]
#
# Env: GH_TOKEN/GITHUB_TOKEN for escalation; GITHUB_OUTPUT for output emission.
set -uo pipefail

NAME=""; FINDINGS_CODES=""; RETRIES=2; RETRY_SLEEP=5; PR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name)           NAME="$2"; shift 2 ;;
    --findings-codes) FINDINGS_CODES="$2"; shift 2 ;;
    --retries)        RETRIES="$2"; shift 2 ;;
    --retry-sleep)    RETRY_SLEEP="$2"; shift 2 ;;
    --pr)             PR="$2"; shift 2 ;;
    --) shift; break ;;
    *) echo "gate_typed_check: unknown arg '$1'" >&2; shift ;;
  esac
done

if [ -z "$NAME" ] || [ $# -eq 0 ]; then
  echo "::error::gate_typed_check: --name and a command (after --) are required" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

emit() {  # emit KEY=VALUE to GITHUB_OUTPUT if available (no-op locally)
  [ -n "${GITHUB_OUTPUT:-}" ] && printf '%s\n' "$1" >> "$GITHUB_OUTPUT"
}

attempt=0
while : ; do
  out_file="$(mktemp 2>/dev/null || echo "/tmp/gate_typed_${NAME}_$$.log")"
  echo "▶ [$NAME] attempt $((attempt + 1))/$((RETRIES + 1)): $*"
  # Run the command, teeing combined output to the log AND capturing the command's
  # OWN exit code via PIPESTATUS[0] (not tee's). The pipe is synchronous — tee has
  # flushed by the time the pipeline returns — so the emptiness check below is race-free.
  # 2>&1 so a crash that only writes to stderr still counts as output. The script does
  # not use `set -e`, so a non-zero rc here does not abort us — we classify it.
  "$@" 2>&1 | tee "$out_file"
  rc=${PIPESTATUS[0]}

  empty_flag=""
  [ -s "$out_file" ] || empty_flag="--output-empty"

  cls="$(python3 "$SCRIPT_DIR/gate_classify_check.py" \
          --rc "$rc" --findings-codes "$FINDINGS_CODES" $empty_flag 2>/dev/null || echo INFRA)"
  echo "  → rc=$rc classify=$cls"

  case "$cls" in
    CLEAN)
      emit "outcome=clean"; emit "infra_error=false"
      echo "✓ [$NAME] clean"
      exit 0 ;;
    FINDINGS)
      emit "outcome=findings"; emit "infra_error=false"
      echo "✗ [$NAME] real finding (rc=$rc) — code FAIL (fixer-eligible)"
      exit 1 ;;
    INFRA)
      if [ "$attempt" -lt "$RETRIES" ]; then
        attempt=$((attempt + 1))
        echo "  ⟳ [$NAME] infra/transient (rc=$rc) — retrying in ${RETRY_SLEEP}s ($attempt/$RETRIES)"
        sleep "$RETRY_SLEEP"
        continue
      fi
      # Persistent infra error: escalate (never fed to fixer, never auto-passed).
      emit "outcome=infra"; emit "infra_error=true"
      DETAIL="$(tail -n 3 "$out_file" 2>/dev/null | tr '\n' ' ' | head -c 300)"
      [ -n "$DETAIL" ] || DETAIL="exit $rc with no output"
      echo "::error::[$NAME] persistent infra error after $((RETRIES + 1)) attempts (rc=$rc) — escalating."
      bash "$SCRIPT_DIR/gate_infra_escalate.sh" \
        --pr "$PR" --check "$NAME" --detail "$DETAIL" || true
      exit 1 ;;
  esac
done
