#!/usr/bin/env bash

# Copyright 2026 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

chart="charts/latest/csi-driver-nfs"
changed_files="$(
  git diff --cached --name-only --diff-filter=ACMRT |
    grep -E "^${chart}/(values[^/]*\.ya?ml|templates/.+)$" || true
)"

if [ -z "$changed_files" ]; then
  exit 0
fi

chart_file="${chart}/Chart.yaml"
[ -f "$chart_file" ] || exit 0

if git diff --cached --unified=0 -- "$chart_file" | grep -qE '^[-+][[:space:]]*version:[[:space:]]*'; then
  echo "chart version already staged: ${chart_file}"
  exit 0
fi

old_version="$(awk '/^[[:space:]]*version:[[:space:]]*/ {print $2; exit}' "$chart_file" | tr -d '"')"
if ! printf '%s\n' "$old_version" | grep -qE '^v?[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "cannot patch-bump ${chart_file}: unsupported version '${old_version}'" >&2
  exit 1
fi

prefix=""
numeric_version="$old_version"
if printf '%s\n' "$old_version" | grep -q '^v'; then
  prefix="v"
  numeric_version="${old_version#v}"
fi

IFS=. read -r major minor patch <<EOF
$numeric_version
EOF
new_version="${prefix}${major}.${minor}.$((patch + 1))"

perl -0pi -e 's{^([[:space:]]*version:[[:space:]]*"?v?)(\d+)\.(\d+)\.(\d+)("?[[:space:]]*)$}{$1 . $2 . "." . $3 . "." . ($4 + 1) . $5}em' "$chart_file"

git add "$chart_file"
echo "patch-bumped ${chart_file}: ${old_version} -> ${new_version}"
