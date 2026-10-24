#!/usr/bin/env bash
# Writes the Trivy report as markdown and blocks nightly builds with vulnerabilities.
# Reads SCAN_OUTCOME, REPORT, REPORT_MD, NIGHTLY, SEVERITY and VARIANT,
# writes to GITHUB_OUTPUT, GITHUB_STEP_SUMMARY and REPORT_MD.
set -euo pipefail

max_rows=100
title="Trivy scan${VARIANT:+ ($VARIANT)}"

finish() {
  cat "$REPORT_MD" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
}
trap finish EXIT

if [[ "$SCAN_OUTCOME" != "success" || ! -f "$REPORT" ]]; then
  echo "vulnerabilities=" >> "$GITHUB_OUTPUT"
  echo "### $title failed" > "$REPORT_MD"
  if [[ "$NIGHTLY" == "true" ]]; then
    echo "::error::Trivy scan failed, the nightly image is not pushed"
    exit 1
  fi
  echo "::warning::Trivy scan failed"
  exit 0
fi

count=$(jq '[.Results[]?.Vulnerabilities[]?] | length' "$REPORT")
echo "vulnerabilities=$count" >> "$GITHUB_OUTPUT"

if (( count == 0 )); then
  echo "### $title: no $SEVERITY vulnerabilities" > "$REPORT_MD"
  exit 0
fi

{
  echo "### $title: $count $SEVERITY vulnerabilities"
  echo ""
  echo "<details>"
  echo "<summary>Vulnerabilities</summary>"
  echo ""
  echo "| Severity | ID | Package | Installed | Fixed | Target |"
  echo "|---|---|---|---|---|---|"
  jq -r --argjson max "$max_rows" '[.Results[]? | .Target as $target | .Vulnerabilities[]?
    | "| \(.Severity) | \(.VulnerabilityID) | \(.PkgName) | \(.InstalledVersion) | \(.FixedVersion // "") | \($target) |"]
    | .[:$max][]' "$REPORT"
  if (( count > max_rows )); then
    echo ""
    echo "And $((count - max_rows)) more."
  fi
  echo ""
  echo "</details>"
} > "$REPORT_MD"

if [[ "$NIGHTLY" == "true" ]]; then
  echo "::error::Trivy found $count $SEVERITY vulnerabilities, the nightly image is not pushed"
  exit 1
fi
echo "::warning::Trivy found $count $SEVERITY vulnerabilities"
