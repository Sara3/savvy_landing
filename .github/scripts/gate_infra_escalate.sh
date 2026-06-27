#!/usr/bin/env bash
# gate_infra_escalate.sh — uniform Type-C (infra/"couldn't run") escalation.
#
# A Type-C failure is NEITHER a passing check (we never proved the code is safe)
# NOR a code rejection (it is not the PR's fault). This script makes that explicit
# and human-visible, identically for every gate check:
#
#   1. Ensure the distinct `gate-infra-error` label exists (idempotent).
#   2. Label the PR `gate-infra-error` + `needs-human-review` so it leaves the
#      auto-merge path and enters the human queue, tagged as an infra failure
#      (NOT "your code was rejected").
#   3. Open OR update a single DEDUPED tracking issue per failing check class
#      (dedup key = a hidden marker in the issue body). Repeat occurrences add a
#      comment instead of spawning a new issue — so a flaky check yields ONE
#      issue with a running log, not a pile.
#   4. Post a sticky PR comment explaining "couldn't verify (infra) — not a code
#      rejection", so the PR author/ reviewer is never misled.
#
# All gh calls are best-effort (|| true) AFTER the routing decision is made — the
# caller has already decided to BLOCK (exit non-zero). This script only annotates;
# it must never itself flip a block into a pass.
#
# Usage:
#   gate_infra_escalate.sh --pr <num> --check <name> --detail "<one-line cause>" \
#       [--run-url <actions-run-url>] [--repo <owner/repo>]
#
# Env: GH_TOKEN (or GITHUB_TOKEN) must be set for the gh calls.
set -uo pipefail

PR=""; CHECK=""; DETAIL=""; RUN_URL=""; REPO="${GITHUB_REPOSITORY:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --pr)      PR="$2"; shift 2 ;;
    --check)   CHECK="$2"; shift 2 ;;
    --detail)  DETAIL="$2"; shift 2 ;;
    --run-url) RUN_URL="$2"; shift 2 ;;
    --repo)    REPO="$2"; shift 2 ;;
    *) echo "gate_infra_escalate: unknown arg '$1'" >&2; shift ;;
  esac
done

if [ -z "$CHECK" ]; then
  echo "::error::gate_infra_escalate: --check is required" >&2
  exit 0   # annotation helper — never block on our own arg error
fi

# gh wrapper that appends --repo only when REPO is known (owner/repo has no spaces,
# so this is safe; avoids empty-array expansion under `set -u` on older bash).
ghx() { if [ -n "$REPO" ]; then gh "$@" --repo "$REPO"; else gh "$@"; fi; }

# Derive the run URL if not supplied (so the issue/comment links to the failing run).
if [ -z "$RUN_URL" ] && [ -n "${GITHUB_SERVER_URL:-}" ] && [ -n "${GITHUB_RUN_ID:-}" ]; then
  RUN_URL="${GITHUB_SERVER_URL}/${REPO}/actions/runs/${GITHUB_RUN_ID}"
fi
TS="$(date -u +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown-time')"

echo "::warning::gate-infra-error [$CHECK]: ${DETAIL:-infra error} — routed to human as 'couldn't verify' (NOT a code rejection)."

# 1. Ensure label exists (idempotent; create may fail if it already exists).
ghx label create gate-infra-error \
  --color B60205 \
  --description "Gate could not RUN a check (infra/environment error) — couldn't verify, not a code rejection" \
  >/dev/null 2>&1 || true

# 2. Label the PR (both: distinct infra tag + the human-queue tag).
if [ -n "$PR" ]; then
  ghx issue edit "$PR" --add-label gate-infra-error --add-label needs-human-review \
    >/dev/null 2>&1 || true
fi

# 3. Deduped tracking issue (one per check class). Dedup by a hidden body marker,
# matched with gh's built-in jq (no fragile inline Python in a command sub).
ISSUE_MARKER="<!-- gate-infra:${CHECK} -->"
EXISTING_ID="$(ghx issue list --state open --label gate-infra-error --limit 100 \
  --json number,body \
  --jq "map(select(.body | contains(\"$ISSUE_MARKER\"))) | .[0].number // empty" \
  2>/dev/null || true)"

OCCURRENCE="- ${TS} — PR #${PR:-?}${RUN_URL:+ — [run](${RUN_URL})}: ${DETAIL:-infra error}"

if [ -n "$EXISTING_ID" ]; then
  ghx issue comment "$EXISTING_ID" \
    --body "Recurred (gate could not run \`${CHECK}\`):
${OCCURRENCE}" >/dev/null 2>&1 || true
  echo "gate-infra-error: appended occurrence to tracking issue #${EXISTING_ID}"
else
  BODY="$(printf '%s\n\n%s\n\n%s\n\n%s\n' \
    "${ISSUE_MARKER}" \
    "**The savvy gate could not RUN the \`${CHECK}\` check** (Type-C / infra error). This is an environment/setup failure, **not** a code rejection — the affected PR(s) were routed to human review as \"couldn't verify\", never auto-passed and never chased by the auto-fixer." \
    "This is a **deduped** tracking issue — each recurrence appends a comment below instead of opening a new issue. Close it once the underlying infra cause (runner, registry, tool install, OOM, timeout, external API) is fixed." \
    "### Occurrences
${OCCURRENCE}")"
  ghx issue create \
    --title "[gate-infra] ${CHECK} — gate could not run (infra error)" \
    --label gate-infra-error \
    --body "$BODY" >/dev/null 2>&1 || true
  echo "gate-infra-error: opened tracking issue for check '${CHECK}'"
fi

# 4. Sticky PR comment (one per check class; updated in place).
if [ -n "$PR" ]; then
  CMARKER="<!-- gate-infra-comment:${CHECK} -->"
  BODY_FILE="$(mktemp 2>/dev/null || echo /tmp/gate_infra_comment.md)"
  {
    echo "$CMARKER"
    echo "### 🛠️ Gate infra error — could not verify (Type-C)"
    echo ""
    printf 'The **%s** check could not run to a trustworthy conclusion: `%s`\n' "$CHECK" "${DETAIL:-infra error}"
    echo ""
    echo "This is an **infrastructure/environment failure, not a code rejection.** Per the gate's Type-C contract this PR was:"
    echo "- **not auto-passed** (we never proved the code is safe), and"
    echo "- **not chased by the auto-fixer** (there is nothing in the code to fix), and"
    echo "- **routed to a human** with the \`gate-infra-error\` label + a deduped tracking issue."
    echo ""
    echo "Re-run the gate once the infra cause is resolved. ${RUN_URL:+[Failing run](${RUN_URL})}"
    echo ""
    echo "_— savvy gate · Type-C escalation_"
  } > "$BODY_FILE"

  CID="$(gh api "repos/${REPO}/issues/${PR}/comments" --paginate \
    --jq ".[]|select(.body|contains(\"$CMARKER\"))|.id" 2>/dev/null | head -1)"
  if [ -n "$CID" ]; then
    gh api -X PATCH "repos/${REPO}/issues/comments/${CID}" \
      -f body="$(cat "$BODY_FILE")" >/dev/null 2>&1 || true
  else
    ghx pr comment "$PR" --body-file "$BODY_FILE" >/dev/null 2>&1 || true
  fi
fi

exit 0
