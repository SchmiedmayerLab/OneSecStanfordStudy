#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
# SPDX-License-Identifier: MIT
#

set -euo pipefail
cd "$(dirname "$0")/.."

baseline="${1:-origin/main}"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/one-sec-api.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT

platform_version="$(swift package dump-package | jq -r '.platforms[] | select(.platformName == "ios") | .version')"
test -n "$platform_version"
triple="arm64-apple-ios${platform_version}-simulator"
jq -n --arg triple "$triple" \
  '{schemaVersion: "1.0", swiftCompiler: {extraCLIOptions: ["-target", $triple]}}' \
  > "$check_dir/toolset.json"

swift package \
  --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  --triple "$triple" \
  --toolset "$check_dir/toolset.json" \
  diagnose-api-breaking-changes "$baseline" \
  --products OneSecStanfordStudy \
  --breakage-allowlist-path .github/api-breakages.txt
