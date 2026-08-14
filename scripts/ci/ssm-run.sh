#!/bin/bash
# Shared by cd.yml and refresh-ecr-creds.yml: send an AWS-RunShellScript SSM
# command to an instance, wait for it, and print its stdout.
#
# Builds the --parameters payload with jq instead of hand-escaped shell
# strings — a prior version built `commands="[ \"...\" ]"` by hand, which is
# exactly the kind of three-layer quoting (YAML block scalar -> bash
# double-quoted string -> SSM commands array) that's easy to get wrong (it
# already had one instance where an unescaped `$(...)` was evaluated at the
# wrong time). jq handles arbitrary characters in each command correctly, no
# manual escaping required.
#
# Usage: ssm-run.sh <instance-id> <command...>
# Prints StandardOutputContent to stdout on success; exits 1 (with
# StandardErrorContent on stderr) on Failed/Cancelled/TimedOut/timeout.
set -euo pipefail

INSTANCE_ID="$1"
shift

PARAMS=$(jq -n --args '{"commands": $ARGS.positional}' "$@")

CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "$PARAMS" \
  --query "Command.CommandId" --output text)

# FAIL_COUNT tolerates the brief propagation delay right after send-command
# (the invocation can be briefly not-yet-visible on the instance) without
# masking a real, persistent failure (AccessDenied, throttling, a
# deregistered instance) as ordinary "still running" for the full 300s
# budget — a prior version treated every possible CLI error identically to
# "not found yet" and discarded stderr, so a permissions/infra problem and
# normal polling looked the same in the logs.
#
# stderr is captured to its own file, not merged into RESULT via 2>&1: the
# aws CLI can write non-fatal warnings to stderr even on a zero-exit call
# (botocore/urllib3 deprecation notices are common on GitHub-hosted
# runners), and RESULT must stay pure JSON for the unconditional `jq -r
# .Status` below — a prior version merged them and one such warning would
# corrupt the JSON, crashing the whole script under set -e instead of
# reporting a clean failure.
STDERR_FILE=$(mktemp)
trap 'rm -f "$STDERR_FILE"' EXIT

# POLL_COUNT is the ~300s budget for the command to actually finish;
# FAIL_COUNT and UNKNOWN_COUNT are separate strike counters that fail fast
# (3 strikes, ~30s) without consuming from it. A prior version used a single
# `for i in $(seq 1 30)` counter for everything, so a few transient
# get-command-invocation errors (API throttling, network blip) ate into the
# same budget a genuinely slow-but-healthy command needed to finish in,
# risking a false "timed out" on an otherwise-fine deploy.
FAIL_COUNT=0
UNKNOWN_COUNT=0
POLL_COUNT=0
while [ "$POLL_COUNT" -lt 30 ]; do
  if ! RESULT=$(aws ssm get-command-invocation \
    --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
    --output json 2>"$STDERR_FILE"); then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "aws ssm get-command-invocation failed (attempt $FAIL_COUNT/3): $(cat "$STDERR_FILE")" >&2
    if [ "$FAIL_COUNT" -ge 3 ]; then
      echo "Giving up after $FAIL_COUNT consecutive get-command-invocation failures for $CMD_ID" >&2
      exit 1
    fi
    sleep 10
    continue
  fi
  FAIL_COUNT=0
  POLL_COUNT=$((POLL_COUNT + 1))
  STATUS=$(echo "$RESULT" | jq -r .Status)
  echo "SSM command $CMD_ID status: $STATUS" >&2
  case "$STATUS" in
    Success)
      echo "$RESULT" | jq -r .Output
      exit 0
      ;;
    Failed | Cancelled | TimedOut)
      echo "$RESULT" | jq -r .Error >&2
      exit 1
      ;;
    Pending | InProgress | Delayed | Cancelling)
      UNKNOWN_COUNT=0 # a known status means the API is behaving normally again
      ;;
    *)
      # Same fail-fast treatment as CLI-call errors above: an unrecognized
      # Status (API change, new/undocumented value, region quirk) is at
      # least as suspicious as a CLI exception and shouldn't be allowed to
      # silently burn the full polling budget before surfacing.
      UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1))
      echo "::warning::Unrecognized SSM status '$STATUS' for command $CMD_ID (strike $UNKNOWN_COUNT/3) — continuing to poll" >&2
      if [ "$UNKNOWN_COUNT" -ge 3 ]; then
        echo "Giving up after $UNKNOWN_COUNT consecutive unrecognized statuses ('$STATUS') for $CMD_ID" >&2
        exit 1
      fi
      ;;
  esac
  sleep 10
done
echo "Timed out waiting for SSM command $CMD_ID" >&2
exit 1
