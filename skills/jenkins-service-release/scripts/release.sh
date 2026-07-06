#!/usr/bin/env bash
# Jenkins 并行发版脚本
set -euo pipefail

JENKINS_USER=$(cat /Users/jackson/secret/jenkins/username)
JENKINS_TOKEN=$(cat /Users/jackson/secret/jenkins/api_token)
JENKINS_URL="https://jenkins.designorder.cn"
JOB="build_general_service_image"
POLL_INTERVAL=30
TIMEOUT=1800

SERVICE_TYPE=""
ENV_TYPE=""

usage() {
  echo "Usage: $0 --service projection|dataproc --env preprod|refactor"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service) SERVICE_TYPE="$2"; shift 2 ;;
    --env) ENV_TYPE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$SERVICE_TYPE" && -n "$ENV_TYPE" ]] || usage

case "$SERVICE_TYPE" in
  projection) SERVICES=("ai-python-auto-dimension" "ai-python-auto-dimension-part") ;;
  dataproc)   SERVICES=("ai-algorithm-stp-convert") ;;
  *) echo "Unknown service: $SERVICE_TYPE"; exit 1 ;;
esac

case "$ENV_TYPE" in
  preprod)  PROFILE="production"; BRANCH="release" ;;
  refactor) PROFILE="suanfa";     BRANCH="dev" ;;
  *) echo "Unknown env: $ENV_TYPE"; exit 1 ;;
esac

CRUMB_JSON=$(curl -sS -u "$JENKINS_USER:$JENKINS_TOKEN" "$JENKINS_URL/crumbIssuer/api/json")
CRUMB=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumb'])")
CRUMB_FIELD=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumbRequestField'])")

declare -A SERVICE_QUEUE=()

trigger_one() {
  local svc="$1"
  local hdr
  hdr=$(mktemp)
  local code
  code=$(curl -sS -D "$hdr" -o /dev/null -w '%{http_code}' -X POST \
    -u "$JENKINS_USER:$JENKINS_TOKEN" \
    -H "$CRUMB_FIELD: $CRUMB" \
    "$JENKINS_URL/job/$JOB/buildWithParameters" \
    --data-urlencode "collection=python-ai" \
    --data-urlencode "serviceName=$svc" \
    --data-urlencode "profile=$PROFILE" \
    --data-urlencode "branch=$BRANCH" \
    --data-urlencode "CleanWorkSpace=false" \
    --data-urlencode "DeployToK8S=true" \
    --data-urlencode "Rsync=false" \
    --data-urlencode "Reverse=true")
  if [[ "$code" != "201" && "$code" != "302" ]]; then
    echo "ERROR: trigger $svc failed HTTP $code"
    rm -f "$hdr"
    exit 1
  fi
  local qid
  qid=$(grep -i '^location:' "$hdr" | sed 's|.*/queue/item/||;s|/.*||' | tr -d '\r')
  rm -f "$hdr"
  if [[ -z "$qid" ]]; then
    echo "ERROR: no queue id for $svc"
    exit 1
  fi
  SERVICE_QUEUE["$svc"]="$qid"
  echo "Triggered $svc -> queue $qid"
}

declare -A SERVICE_BUILD=()

resolve_build_no() {
  local qid="$1"
  local i build_no=""
  for i in $(seq 1 30); do
    build_no=$(curl -sS -u "$JENKINS_USER:$JENKINS_TOKEN" \
      "$JENKINS_URL/queue/item/$qid/api/json" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); e=d.get('executable'); print(e.get('number','') if e else '')" 2>/dev/null || true)
    if [[ -n "$build_no" ]]; then
      echo "$build_no"
      return 0
    fi
    sleep 2
  done
  return 1
}

echo "=== Trigger (parallel) profile=$PROFILE branch=$BRANCH ==="
for svc in "${SERVICES[@]}"; do
  trigger_one "$svc" &
done
wait

echo "=== Resolve build numbers ==="
for svc in "${SERVICES[@]}"; do
  qid="${SERVICE_QUEUE[$svc]}"
  build_no=$(resolve_build_no "$qid") || { echo "ERROR: timeout resolving build for $svc (queue $qid)"; exit 1; }
  SERVICE_BUILD["$svc"]="$build_no"
  echo "$svc -> build #$build_no"
done

echo "=== Wait for builds ==="
declare -A SERVICE_RESULT=()
declare -A SERVICE_DISPLAY=()
ELAPSED=0
PENDING=("${SERVICES[@]}")

while [[ $ELAPSED -lt $TIMEOUT && ${#PENDING[@]} -gt 0 ]]; do
  STILL=()
  for svc in "${PENDING[@]}"; do
    build_no="${SERVICE_BUILD[$svc]}"
    read -r building result display < <(curl -sS -u "$JENKINS_USER:$JENKINS_TOKEN" \
      "$JENKINS_URL/job/$JOB/$build_no/api/json?tree=building,result,displayName" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('building',True), d.get('result') or 'RUNNING', d.get('displayName',''))")
    if [[ "$building" == "False" ]]; then
      SERVICE_RESULT["$svc"]="${result:-UNKNOWN}"
      SERVICE_DISPLAY["$svc"]="$display"
      echo "[$ELAPSED s] $svc #$build_no -> $result ($display)"
    else
      echo "[$ELAPSED s] $svc #$build_no -> RUNNING ($display)"
      STILL+=("$svc")
    fi
  done
  PENDING=("${STILL[@]}")
  [[ ${#PENDING[@]} -eq 0 ]] && break
  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [[ ${#PENDING[@]} -gt 0 ]]; then
  echo "ERROR: timeout waiting for: ${PENDING[*]}"
  exit 1
fi

echo ""
echo "=== Summary ==="
echo "Environment: profile=$PROFILE branch=$BRANCH"
FAIL=0
for svc in "${SERVICES[@]}"; do
  build_no="${SERVICE_BUILD[$svc]}"
  result="${SERVICE_RESULT[$svc]}"
  display="${SERVICE_DISPLAY[$svc]}"
  echo "- $svc: build #$build_no | $result | $display"
  echo "  console: $JENKINS_URL/job/$JOB/$build_no/console"
  [[ "$result" != "SUCCESS" ]] && FAIL=1
done
exit "$FAIL"
