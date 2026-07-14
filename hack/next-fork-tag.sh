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

repo_root="$(git rev-parse --show-toplevel)"
readonly repo_root
readonly commit="${1:-HEAD}"
upstream_version="$(
  awk '$1 == "IMAGE_VERSION" && $2 == "?=" { print $3; exit }' \
    "${repo_root}/Makefile"
)"
readonly upstream_version

if [[ ! "${upstream_version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'invalid IMAGE_VERSION in %s/Makefile: %s\n' \
    "${repo_root}" "${upstream_version:-<missing>}" >&2
  exit 1
fi

target_commit="$(git rev-parse --verify "${commit}^{commit}")"
readonly target_commit

revision_for_tag() {
  local tag="$1"
  local revision

  case "${tag}" in
    "${upstream_version}-ym")
      printf '1\n'
      ;;
    "${upstream_version}-ym2")
      printf '2\n'
      ;;
    "${upstream_version}-ym."*)
      revision="${tag#"${upstream_version}-ym."}"
      if [[ "${revision}" =~ ^[1-9][0-9]*$ ]]; then
        printf '%d\n' "$((10#${revision}))"
      else
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

max_revision=0
existing_revision=0
existing_tag=""

while IFS= read -r tag; do
  if ! revision="$(revision_for_tag "${tag}")"; then
    continue
  fi

  if ((revision > max_revision)); then
    max_revision="${revision}"
  fi

  if [[ "$(git rev-list -n 1 "${tag}")" == "${target_commit}" ]] && \
    ((revision > existing_revision)); then
    existing_revision="${revision}"
    existing_tag="${tag}"
  fi
done < <(git tag --list "${upstream_version}-ym*")

if [[ -n "${existing_tag}" ]]; then
  printf 'tag=%s\n' "${existing_tag}"
  printf 'create=false\n'
  exit 0
fi

printf 'tag=%s-ym.%d\n' "${upstream_version}" "$((max_revision + 1))"
printf 'create=true\n'
