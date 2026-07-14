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

if (($# != 2)); then
  printf 'usage: %s <release-tag> <commit-sha>\n' "$0" >&2
  exit 2
fi

readonly tag="$1"
readonly commit="$2"
: "${FORGEJO_API_URL:?FORGEJO_API_URL is required}"
: "${FORGEJO_REPOSITORY:?FORGEJO_REPOSITORY is required}"
: "${FORGEJO_TOKEN:?FORGEJO_TOKEN is required}"

if [[ ! "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-ym\.[1-9][0-9]*$ ]]; then
  printf 'refusing non-canonical release tag: %s\n' "${tag}" >&2
  exit 2
fi
if [[ ! "${commit}" =~ ^[0-9a-f]{40}$ ]]; then
  printf 'refusing invalid commit SHA: %s\n' "${commit}" >&2
  exit 2
fi
if [[ ! "${FORGEJO_API_URL}" =~ ^https?://[^/]+/api/v1$ ]]; then
  printf 'refusing invalid Forgejo API URL\n' >&2
  exit 2
fi
if [[ ! "${FORGEJO_REPOSITORY}" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  printf 'refusing invalid Forgejo repository name\n' >&2
  exit 2
fi

response_file="$(mktemp)"
readonly response_file
trap 'rm -f "${response_file}"' EXIT

payload="$(printf '{"tag_name":"%s","target":"%s"}' "${tag}" "${commit}")"
readonly payload
status="$(curl --silent --show-error \
  --output "${response_file}" \
  --write-out '%{http_code}' \
  --request POST \
  --header "Authorization: token ${FORGEJO_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data "${payload}" \
  "${FORGEJO_API_URL}/repos/${FORGEJO_REPOSITORY}/tags")"
readonly status

case "${status}" in
  201)
    printf 'created immutable release tag %s at %s\n' "${tag}" "${commit}"
    ;;
  409)
    printf 'release tag conflict: %s already exists and was not moved\n' \
      "${tag}" >&2
    exit 1
    ;;
  *)
    printf 'Forgejo tag creation failed with HTTP %s: ' "${status}" >&2
    cat "${response_file}" >&2
    exit 1
    ;;
esac
