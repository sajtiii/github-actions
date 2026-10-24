#!/usr/bin/env bash
# Resolves the build: registry host, image name, Dockerfile, platforms, whether QEMU is needed,
# the platform to scan, the Trivy ignore file, whether it is a nightly build, the cache scope,
# the tag rules and whether to push.
# Reads REGISTRY, IMAGE, CONTEXT, FILE, PLATFORMS, RUNNER_ARCH, PUSH, LATEST, VARIANT,
# VARIANT_DEFAULT, EVENT_NAME, REF, DEFAULT_BRANCH, REPOSITORY and PR_HEAD_REPOSITORY,
# writes to GITHUB_OUTPUT.
# The upper case variables are set by the action, so they are not misspelled locals
# shellcheck disable=SC2153
set -euo pipefail

# Action inputs are untyped strings, so validate them here
errors=0
error() {
  echo "::error::$1"
  errors=$((errors + 1))
}

for input in "push=$PUSH" "variant-default=$VARIANT_DEFAULT"; do
  [[ "${input#*=}" == "true" || "${input#*=}" == "false" ]] \
    || error "Input ${input%%=*} must be true or false, got '${input#*=}'"
done

case "$REGISTRY" in
  ghcr) host=ghcr.io ;;
  *) error "Input registry must be one of: ghcr, got '$REGISTRY'" ;;
esac

if [[ -n "$VARIANT" && ! "$VARIANT" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  error "Input variant may only contain letters, digits, '.', '_' and '-', got '$VARIANT'"
fi
if [[ "$VARIANT_DEFAULT" == "true" && -z "$VARIANT" ]]; then
  error "Input variant-default needs a variant"
fi

(( errors == 0 )) || exit 1

case "$RUNNER_ARCH" in
  X64) native=linux/amd64 ;;
  ARM64) native=linux/arm64 ;;
  ARM) native=linux/arm/v7 ;;
  X86) native=linux/386 ;;
  *) native="" ;;
esac

mapfile -t platforms < <(tr ',' '\n' <<< "$PLATFORMS" | tr -d '[:blank:]' | grep -v '^$' || true)
qemu=false
if (( ${#platforms[@]} > 1 )) || { (( ${#platforms[@]} == 1 )) && [[ "${platforms[0]}" != "$native" ]]; }; then
  qemu=true
fi

# Scan the runner's platform when it is built, otherwise the first one
scan_platform="$native"
if (( ${#platforms[@]} > 0 )) && [[ " ${platforms[*]} " != *" $native "* ]]; then
  scan_platform="${platforms[0]}"
fi
(( ${#platforms[@]} > 0 )) || platforms=("$native")

file="${FILE:-${CONTEXT%/}/Dockerfile}"

trivyignores=""
if [[ -f .trivyignore.yaml ]]; then
  trivyignores=.trivyignore.yaml
fi

# Scheduled and manual runs are nightly builds
nightly=false
if [[ "$EVENT_NAME" == "schedule" || "$EVENT_NAME" == "workflow_dispatch" ]]; then
  nightly=true
fi

if [[ "$nightly" == "true" ]]; then
  rules=("type=raw,value=nightly")
  latest=false
else
  rules=(
    "type=edge"
    "type=ref,event=pr"
    "type=semver,pattern=v{{version}}"
    "type=semver,pattern=v{{major}}.{{minor}}"
    "type=semver,pattern=v{{major}}"
  )
  latest="$LATEST"
fi

# Variants get suffixed tags, the default variant (or no variant) gets the plain ones too
tags=()
if [[ -z "$VARIANT" || "$VARIANT_DEFAULT" == "true" ]]; then
  tags+=("${rules[@]}")
  [[ "$latest" == "true" ]] && tags+=("type=raw,value=latest")
fi
if [[ -n "$VARIANT" ]]; then
  for rule in "${rules[@]}"; do
    tags+=("$rule,suffix=-$VARIANT")
  done
  [[ "$latest" == "true" ]] && tags+=("type=raw,value=$VARIANT")
fi

cache_scope="${VARIANT:-buildkit}"

# Push only when one of the tag rules above matches, and the token can write packages
push=true
push_reason=""
if [[ "$PUSH" != "true" ]]; then
  push=false
  push_reason="disabled by the push input"
elif [[ "$EVENT_NAME" == "pull_request" && "$PR_HEAD_REPOSITORY" != "$REPOSITORY" ]]; then
  push=false
  push_reason="pull request from a fork"
elif [[ "$nightly" != "true" && "$EVENT_NAME" != "pull_request" && "$LATEST" != "true" && "$REF" != "refs/heads/$DEFAULT_BRANCH" \
  && ! "$REF" =~ ^refs/tags/v?[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  push=false
  push_reason="no tags for $REF"
fi

{
  echo "host=$host"
  echo "image=$host/${IMAGE,,}"
  echo "file=$file"
  echo "platforms=$(IFS=,; echo "${platforms[*]}")"
  echo "qemu=$qemu"
  echo "scan-platform=$scan_platform"
  echo "trivyignores=$trivyignores"
  echo "nightly=$nightly"
  echo "cache-scope=$cache_scope"
  echo "push=$push"
  echo "push-reason=$push_reason"
  echo "tags<<EOF"
  printf '%s\n' "${tags[@]}"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
