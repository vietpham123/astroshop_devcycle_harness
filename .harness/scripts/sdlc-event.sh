#!/usr/bin/env sh
# Send one SDLC task event to Dynatrace OpenPipeline (events.sdlc).
# Usage: sdlc-event.sh <event.type> <task.name> <harness-status> <start-epoch-ms>
# Field names follow the Dynatrace SDLC event semantics used by the CI/CD Observability app
# and the SDLC / Release Comparison dashboards (event.kind=SDLC_EVENT is set by the endpoint).
# Never fails the pipeline: observability must not block delivery.
set -u
EVENT_TYPE="$1"; TASK_NAME="$2"; HARNESS_STATUS="$3"; START_MS="${4:-}"

case "$(echo "$HARNESS_STATUS" | tr '[:upper:]' '[:lower:]')" in
  success|succeeded|ignorefailed) OUTCOME=Success ;;
  aborted|abortedbyfreeze|discontinuing) OUTCOME=Cancelled ;;
  skipped) OUTCOME=Skipped ;;
  *) OUTCOME=Failure ;;
esac

now_ms() { date +%s%3N 2>/dev/null | grep -E '^[0-9]{13}$' || echo "$(date +%s)000"; }
END_MS=$(now_ms)
[ -z "$START_MS" ] && START_MS="$END_MS"
iso() { s=$(( $1 / 1000 )); ms=$(( $1 % 1000 )); printf '%s.%03dZ' "$(date -u -d "@$s" +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -r "$s" +%Y-%m-%dT%H:%M:%S)" "$ms"; }

BODY=$(cat <<EOF
{
  "event.provider": "harness",
  "event.category": "task",
  "event.type": "${EVENT_TYPE}",
  "event.status": "finished",
  "task.name": "${TASK_NAME}",
  "task.outcome": "${OUTCOME}",
  "start_time": "$(iso "$START_MS")",
  "end_time": "$(iso "$END_MS")",
  "duration": $(( END_MS - START_MS )),
  "artifact.name": "${ARTIFACT_NAME:-astroshop}",
  "artifact.version": "${ARTIFACT_VERSION:-}",
  "artifact.id": "${ARTIFACT_ID:-}",
  "cicd.pipeline.id": "${PIPELINE_ID:-}",
  "cicd.pipeline.name": "${PIPELINE_NAME:-}",
  "cicd.pipeline.run.id": "${RUN_ID:-}",
  "cicd.pipeline.run.url.full": "${RUN_URL:-}",
  "vcs.repository.url.full": "${REPO_URL:-}",
  "vcs.ref.head.name": "${GIT_BRANCH:-}",
  "vcs.ref.head.revision": "${GIT_SHA:-}",
  "deployment.environment.name": "${DEPLOY_ENV:-}"
}
EOF
)

if [ "${DRY_RUN:-0}" = "1" ]; then echo "$BODY"; exit 0; fi

code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${DT_ENV_URL%/}/platform/ingest/v1/events.sdlc" \
  -H "Authorization: Api-Token ${DT_INGEST_TOKEN}" -H 'Content-Type: application/json' -d "$BODY") || code=000
echo "sdlc-event ${EVENT_TYPE}/${ARTIFACT_NAME:-astroshop} outcome=${OUTCOME} → HTTP ${code}"
exit 0
