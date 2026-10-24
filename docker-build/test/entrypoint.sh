#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")/.." && pwd)"
fixtures="$dir/test/fixtures"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

# Usage: check <script> "<expected outputs | error>" [VAR=value...]
# Every expected key=value must be among the outputs, "error" expects a non-zero exit.
check() {
  local script="$1" expected="$2" output
  shift 2
  : > "$tmp/output"
  if env GITHUB_OUTPUT="$tmp/output" GITHUB_STEP_SUMMARY="$tmp/summary" REPORT_MD="$tmp/report.md" "$@" bash "$dir/$script" > /dev/null; then
    output="$(paste -sd ' ' "$tmp/output")"
  else
    output="error"
  fi

  local ok=true pair
  for pair in $expected; do
    [[ " $output " == *" $pair "* ]] || ok=false
  done

  local args="$*"
  if $ok; then
    echo "ok   $script ${args//$'\n'/;}"
  else
    echo "FAIL $script ${args//$'\n'/;}"
    echo "     expected: $expected"
    echo "     got:      $output"
    failures=$((failures + 1))
  fi
}

defaults=(REGISTRY=ghcr IMAGE=sajtiii/app CONTEXT=. FILE= PLATFORMS= RUNNER_ARCH=X64 PUSH=true
  LATEST=false VARIANT= VARIANT_DEFAULT=false EVENT_NAME=push REF=refs/heads/main DEFAULT_BRANCH=main
  REPOSITORY=sajtiii/app PR_HEAD_REPOSITORY=)

resolve() {
  check resolve.sh "$1" "${defaults[@]}" "${@:2}"
}

# Usage: tags "<expected rules, one per line>" [VAR=value...]
tags() {
  local expected="$1" output
  shift
  : > "$tmp/output"
  env GITHUB_OUTPUT="$tmp/output" "${defaults[@]}" "$@" bash "$dir/resolve.sh"
  output="$(sed -n '/^tags<<EOF$/,/^EOF$/p' "$tmp/output" | sed '1d;$d')"
  if [[ "$output" == "$expected" ]]; then
    echo "ok   tags $*"
  else
    echo "FAIL tags $*"
    echo "     expected: ${expected//$'\n'/; }"
    echo "     got:      ${output//$'\n'/; }"
    failures=$((failures + 1))
  fi
}

resolve "host=ghcr.io image=ghcr.io/sajtiii/app"
resolve "image=ghcr.io/sajtiii/app" IMAGE=Sajtiii/App
resolve "error" REGISTRY=dockerhub
resolve "error" PUSH=yes
resolve "error" PUSH=
resolve "error" VARIANT_DEFAULT=1 VARIANT=php8.5
resolve "error" VARIANT_DEFAULT=true
resolve "error" "VARIANT=php 8.5"
resolve "error" VARIANT=php8.5/fpm
resolve "cache-scope=php_8.5-fpm" VARIANT=php_8.5-fpm VARIANT_DEFAULT=true

resolve "qemu=false scan-platform=linux/amd64"
resolve "qemu=false scan-platform=linux/amd64" PLATFORMS=linux/amd64
resolve "qemu=false scan-platform=linux/amd64" "PLATFORMS= linux/amd64 "
resolve "qemu=true scan-platform=linux/arm64" PLATFORMS=linux/arm64
resolve "qemu=false scan-platform=linux/arm64" PLATFORMS=linux/arm64 RUNNER_ARCH=ARM64
resolve "qemu=true scan-platform=linux/amd64" PLATFORMS=linux/amd64 RUNNER_ARCH=ARM64
resolve "qemu=true scan-platform=linux/amd64" "PLATFORMS=linux/arm64, linux/amd64"
resolve "qemu=true scan-platform=linux/amd64" $'PLATFORMS=linux/amd64\nlinux/arm64'
resolve "qemu=true scan-platform=linux/arm64" PLATFORMS=linux/arm64,linux/arm/v7

# The Trivy ignore file is looked up in the working directory
resolve "trivyignores="
mkdir "$tmp/ignore" && touch "$tmp/ignore/.trivyignore.yaml"
pushd "$tmp/ignore" > /dev/null
resolve "trivyignores=.trivyignore.yaml"
popd > /dev/null

resolve "platforms=linux/amd64"
resolve "platforms=linux/arm64" RUNNER_ARCH=ARM64
resolve "platforms=linux/amd64,linux/arm64" "PLATFORMS=linux/amd64, linux/arm64"

resolve "file=./Dockerfile"
resolve "file=app/Dockerfile" CONTEXT=app/
resolve "file=docker/prod.Dockerfile" CONTEXT=app FILE=docker/prod.Dockerfile

resolve "push=true push-reason= nightly=false"
resolve "nightly=false" EVENT_NAME=release REF=refs/tags/v1.2.3
resolve "nightly=false" EVENT_NAME=pull_request REF=refs/pull/1/merge PR_HEAD_REPOSITORY=sajtiii/app
resolve "push=true nightly=true" EVENT_NAME=workflow_dispatch
resolve "push=true" EVENT_NAME=push REF=refs/tags/v1.2.3
resolve "push=true" EVENT_NAME=release REF=refs/tags/1.2.3
resolve "push=true" EVENT_NAME=release REF=refs/tags/first-release LATEST=true
resolve "push=true" EVENT_NAME=pull_request REF=refs/pull/1/merge PR_HEAD_REPOSITORY=sajtiii/app
resolve "push=true nightly=true" EVENT_NAME=schedule REF=refs/heads/main DEFAULT_BRANCH=
resolve "push=true nightly=true" EVENT_NAME=workflow_dispatch REF=refs/heads/feature
resolve "push=false push-reason=disabled" PUSH=false
resolve "push=false" EVENT_NAME=pull_request REF=refs/pull/1/merge PR_HEAD_REPOSITORY=someone/app
resolve "push=false" EVENT_NAME=push REF=refs/heads/feature
resolve "push=false" EVENT_NAME=push REF=refs/tags/latest-build

resolve "cache-scope=buildkit"
resolve "cache-scope=php8.5" VARIANT=php8.5

plain=$'type=edge\ntype=ref,event=pr\ntype=semver,pattern=v{{version}}\ntype=semver,pattern=v{{major}}.{{minor}}\ntype=semver,pattern=v{{major}}'
suffixed() {
  echo "${plain//$'\n'/,suffix=-$1$'\n'},suffix=-$1"
}

tags "$plain"
tags "$plain"$'\ntype=raw,value=latest' LATEST=true
tags 'type=raw,value=nightly' EVENT_NAME=schedule LATEST=true
tags "$(suffixed php8.4)" VARIANT=php8.4
tags "$(suffixed php8.4)"$'\ntype=raw,value=php8.4' VARIANT=php8.4 LATEST=true
tags "$plain"$'\ntype=raw,value=latest\n'"$(suffixed php8.5)"$'\ntype=raw,value=php8.5' VARIANT=php8.5 VARIANT_DEFAULT=true LATEST=true
tags $'type=raw,value=nightly\ntype=raw,value=nightly,suffix=-php8.5' VARIANT=php8.5 VARIANT_DEFAULT=true EVENT_NAME=workflow_dispatch LATEST=true

evaluate() {
  check evaluate-scan.sh "$1" SEVERITY=HIGH,CRITICAL "${@:2}"
}

evaluate "vulnerabilities=0" SCAN_OUTCOME=success REPORT="$fixtures/clean.json" NIGHTLY=false
evaluate "vulnerabilities=0" SCAN_OUTCOME=success REPORT="$fixtures/clean.json" NIGHTLY=true
evaluate "vulnerabilities=2" SCAN_OUTCOME=success REPORT="$fixtures/vulnerable.json" NIGHTLY=false
evaluate "error" SCAN_OUTCOME=success REPORT="$fixtures/vulnerable.json" NIGHTLY=true
evaluate "vulnerabilities=" SCAN_OUTCOME=failure REPORT="$tmp/missing.json" NIGHTLY=false
evaluate "error" SCAN_OUTCOME=failure REPORT="$tmp/missing.json" NIGHTLY=true

# Usage: report "<expected line>" [VAR=value...]
report() {
  local expected="$1"
  shift
  env GITHUB_OUTPUT=/dev/null REPORT_MD="$tmp/report.md" SEVERITY=HIGH,CRITICAL NIGHTLY=false VARIANT= "$@" \
    bash "$dir/evaluate-scan.sh" > /dev/null || true
  if grep -qxF -- "$expected" "$tmp/report.md"; then
    echo "ok   report $*"
  else
    echo "FAIL report $*"
    echo "     expected line: $expected"
    sed 's/^/     /' "$tmp/report.md"
    failures=$((failures + 1))
  fi
}

report "### Trivy scan: no HIGH,CRITICAL vulnerabilities" SCAN_OUTCOME=success REPORT="$fixtures/clean.json"
report "### Trivy scan (php8.5): 2 HIGH,CRITICAL vulnerabilities" SCAN_OUTCOME=success REPORT="$fixtures/vulnerable.json" VARIANT=php8.5
report "| CRITICAL | CVE-2025-0001 | openssl | 3.5.1-r0 | 3.5.2-r0 | app (alpine 3.22.2) |" SCAN_OUTCOME=success REPORT="$fixtures/vulnerable.json"
report "### Trivy scan failed" SCAN_OUTCOME=failure REPORT="$tmp/missing.json" NIGHTLY=true

jq '.Results[0].Vulnerabilities = [range(60) as $i | .Results[0].Vulnerabilities[]]' "$fixtures/vulnerable.json" > "$tmp/many.json"
report "And 20 more." SCAN_OUTCOME=success REPORT="$tmp/many.json"

summary_defaults=(VARIANT=php8.5 IMAGE=ghcr.io/sajtiii/app REGISTRY=ghcr EVENT_NAME=push REF=refs/heads/main
  NIGHTLY=false CONTEXT=. FILE=./Dockerfile "PLATFORMS=linux/amd64,linux/arm64" SCAN_PLATFORM=linux/amd64 QEMU=true
  $'BUILD_ARGS=PHP_VERSION=8.5\n' CACHE_SCOPE=php8.5 PUSH_REQUESTED=true PUSH=true PUSH_REASON=
  $'TAGS=ghcr.io/sajtiii/app:edge\nghcr.io/sajtiii/app:edge-php8.5' DIGEST=sha256:abc SCAN_OUTCOME=success
  EVALUATE_OUTCOME=success VULNERABILITIES=0 TRIVYIGNORES= BUILD_OUTCOME=success SIGN_ENABLED=true
  SIGN_OUTCOME=success COSIGN_LOG="$tmp/cosign.log")

# Usage: summary "<jq expression that must be true>" [VAR=value...]
summary() {
  local expression="$1"
  shift
  : > "$tmp/output"
  if env GITHUB_OUTPUT="$tmp/output" GITHUB_STEP_SUMMARY="$tmp/summary" "${summary_defaults[@]}" "$@" \
    bash "$dir/summarize.sh" > /dev/null \
    && sed -n '/^summary<<EOF$/,/^EOF$/p' "$tmp/output" | sed '1d;$d' | jq -e "$expression" > /dev/null; then
    echo "ok   summary $expression"
  else
    echo "FAIL summary $expression $*"
    sed 's/^/     /' "$tmp/output"
    failures=$((failures + 1))
  fi
}

echo "tlog entry created with index: 123456" > "$tmp/cosign.log"
summary '.result == "pushed" and .variant == "php8.5" and .image == "ghcr.io/sajtiii/app"'
summary '.build.platforms == ["linux/amd64", "linux/arm64"] and .build.build_args == ["PHP_VERSION=8.5"] and .build.qemu'
summary '.tags == ["ghcr.io/sajtiii/app:edge", "ghcr.io/sajtiii/app:edge-php8.5"] and .digest == "sha256:abc"'
summary '.trivy.vulnerabilities == 0 and .trivy.outcome == "success"'
summary '.signature.signed and .signature.rekor_log_index == 123456'
summary '.result == "built" and .push.enabled == false and .push.reason == "pull request from a fork" and .signature.reason == "not pushed"' \
  PUSH=false "PUSH_REASON=pull request from a fork" SIGN_ENABLED= SIGN_OUTCOME=
summary '.result == "blocked" and .trivy.vulnerabilities == 2 and .digest == "" and .signature.signed == false' \
  NIGHTLY=true EVALUATE_OUTCOME=failure VULNERABILITIES=2 BUILD_OUTCOME= DIGEST= TAGS= SIGN_ENABLED= SIGN_OUTCOME=
summary '.result == "failed" and .trivy.vulnerabilities == null' SCAN_OUTCOME=failure VULNERABILITIES= BUILD_OUTCOME=failure
summary '.signature.signed == false and .signature.reason == "missing the id-token write permission"' SIGN_ENABLED=false SIGN_OUTCOME=
summary '.signature.signed == false and .signature.reason == "pull request"' EVENT_NAME=pull_request SIGN_ENABLED= SIGN_OUTCOME=
summary '.result == "failed" and .nightly == false and .push.requested == false and .image == ""' \
  NIGHTLY=yes PUSH_REQUESTED=yes PUSH= QEMU= IMAGE= TAGS= DIGEST= SCAN_OUTCOME= EVALUATE_OUTCOME= VULNERABILITIES= \
  BUILD_OUTCOME= SIGN_ENABLED= SIGN_OUTCOME=
rm "$tmp/cosign.log"
summary '.signature.signed and .signature.rekor_log_index == null'

(( failures == 0 )) || { echo "$failures check(s) failed"; exit 1; }
