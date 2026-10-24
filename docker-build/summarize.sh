#!/usr/bin/env bash
# Summarizes what the action did, as JSON in the summary output and as a table in the job summary.
# Reads the resolved build (VARIANT, IMAGE, REGISTRY, CONTEXT, FILE, PLATFORMS, SCAN_PLATFORM, QEMU,
# BUILD_ARGS, CACHE_SCOPE, NIGHTLY, PUSH_REQUESTED, PUSH, PUSH_REASON, EVENT_NAME, REF),
# its results (TAGS, DIGEST, SCAN_OUTCOME, EVALUATE_OUTCOME, VULNERABILITIES, TRIVYIGNORES,
# BUILD_OUTCOME, SIGN_ENABLED, SIGN_OUTCOME, COSIGN_LOG), writes to GITHUB_OUTPUT and GITHUB_STEP_SUMMARY.
set -euo pipefail

# Inputs may be invalid when the resolve step failed, so anything but true is false here
bool() {
  [[ "$1" == "true" ]] && echo true || echo false
}

if [[ "$EVALUATE_OUTCOME" == "failure" ]]; then
  result=blocked
elif [[ "$BUILD_OUTCOME" == "success" ]]; then
  [[ "$PUSH" == "true" ]] && result=pushed || result=built
else
  result=failed
fi

if [[ "$SIGN_OUTCOME" == "success" ]]; then
  signed=true
  sign_reason=""
elif [[ "$result" != "pushed" ]]; then
  signed=false
  sign_reason="not pushed"
elif [[ "$EVENT_NAME" == "pull_request" ]]; then
  signed=false
  sign_reason="pull request"
elif [[ "$SIGN_ENABLED" == "false" ]]; then
  signed=false
  sign_reason="missing the id-token write permission"
else
  signed=false
  sign_reason="cosign failed"
fi

rekor_index=""
if [[ -f "$COSIGN_LOG" ]]; then
  rekor_index="$(sed -n 's/.*tlog entry created with index: *\([0-9]*\).*/\1/p' "$COSIGN_LOG" | head -n 1)"
fi

summary="$(jq -n \
  --arg result "$result" \
  --arg variant "$VARIANT" \
  --arg image "$IMAGE" \
  --arg registry "$REGISTRY" \
  --arg event "$EVENT_NAME" \
  --arg ref "$REF" \
  --argjson nightly "$(bool "$NIGHTLY")" \
  --arg context "$CONTEXT" \
  --arg file "$FILE" \
  --arg platforms "$PLATFORMS" \
  --arg scan_platform "$SCAN_PLATFORM" \
  --argjson qemu "$(bool "$QEMU")" \
  --arg build_args "$BUILD_ARGS" \
  --arg cache_scope "$CACHE_SCOPE" \
  --argjson push_requested "$(bool "$PUSH_REQUESTED")" \
  --argjson push "$(bool "$PUSH")" \
  --arg push_reason "$PUSH_REASON" \
  --arg tags "$TAGS" \
  --arg digest "$DIGEST" \
  --arg scan_outcome "$SCAN_OUTCOME" \
  --arg vulnerabilities "$VULNERABILITIES" \
  --arg trivyignores "$TRIVYIGNORES" \
  --argjson signed "$signed" \
  --arg sign_reason "$sign_reason" \
  --arg rekor_index "$rekor_index" \
  '{
    result: $result,
    variant: $variant,
    image: $image,
    registry: $registry,
    event: $event,
    ref: $ref,
    nightly: $nightly,
    build: {
      context: $context,
      file: $file,
      platforms: ($platforms | split(",") | map(select(. != ""))),
      scan_platform: $scan_platform,
      qemu: $qemu,
      build_args: ($build_args | split("\n") | map(select(. != ""))),
      cache_scope: $cache_scope
    },
    push: {requested: $push_requested, enabled: $push, reason: $push_reason},
    tags: ($tags | split("\n") | map(select(. != ""))),
    digest: $digest,
    trivy: {
      outcome: $scan_outcome,
      severity: "HIGH,CRITICAL",
      vulnerabilities: (if $vulnerabilities == "" then null else ($vulnerabilities | tonumber) end),
      ignore_file: $trivyignores
    },
    signature: {
      signed: $signed,
      reason: $sign_reason,
      rekor_log_index: (if $rekor_index == "" then null else ($rekor_index | tonumber) end)
    }
  }')"

{
  echo "summary<<EOF"
  echo "$summary"
  echo "EOF"
} >> "$GITHUB_OUTPUT"

jq -r '
  def or_dash: if . == null or . == "" or . == [] then "-" else . end;
  "### Docker build" + (if .variant != "" then " (\(.variant))" else "" end) + ": \(.result)",
  "",
  "| | |",
  "|---|---|",
  "| Image | `\(.image)` |",
  "| Event | `\(.event)` on `\(.ref)`" + (if .nightly then ", nightly" else "" end) + " |",
  "| Dockerfile | `\(.build.file)` |",
  "| Platforms | \(.build.platforms | join(", ") | or_dash) |",
  "| Build args | \(.build.build_args | map("`\(.)`") | join("<br>") | or_dash) |",
  "| Push | \(if .push.enabled then "yes" else "no, \(.push.reason)" end) |",
  "| Tags | \(.tags | map("`\(.)`") | join("<br>") | or_dash) |",
  "| Digest | \(if .digest == "" then "-" else "`\(.digest)`" end) |",
  "| Trivy | \(if .trivy.vulnerabilities == null then "scan \(.trivy.outcome | or_dash)" else "\(.trivy.vulnerabilities) \(.trivy.severity) vulnerabilities" end) |",
  "| Signed | \(if .signature.signed then "yes" + (if .signature.rekor_log_index != null then ", Rekor index \(.signature.rekor_log_index)" else "" end) else "no, \(.signature.reason)" end) |"
' <<< "$summary" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
