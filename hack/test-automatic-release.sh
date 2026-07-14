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

REPO_ROOT="$(git rev-parse --show-toplevel)"
readonly REPO_ROOT
readonly TAG_RESOLVER="${REPO_ROOT}/hack/next-fork-tag.sh"
readonly TAG_CREATOR="${REPO_ROOT}/hack/create-forgejo-tag.sh"
readonly LINUX_WORKFLOW="${REPO_ROOT}/.github/workflows/linux.yaml"
readonly MAKEFILE="${REPO_ROOT}/Makefile"
TMP_ROOT="$(mktemp -d)"
readonly TMP_ROOT

trap 'rm -rf "${TMP_ROOT}"' EXIT

new_repo() {
  local version="$1"
  local repo

  repo="$(mktemp -d "${TMP_ROOT}/repo.XXXXXX")"
  git -C "${repo}" init -q
  git -C "${repo}" config user.name "Release Test"
  git -C "${repo}" config user.email "release-test@example.invalid"
  git -C "${repo}" config commit.gpgSign false
  git -C "${repo}" config tag.gpgSign false
  printf 'IMAGE_VERSION ?= %s\n' "${version}" > "${repo}/Makefile"
  printf '%s\n' "${repo}"
}

commit_state() {
  local repo="$1"
  local state="$2"

  printf '%s\n' "${state}" > "${repo}/state"
  git -C "${repo}" add Makefile state
  git -C "${repo}" commit -q -m "${state}"
  git -C "${repo}" rev-parse HEAD
}

resolve_tag() {
  local repo="$1"
  local commit="$2"

  (cd "${repo}" && "${TAG_RESOLVER}" "${commit}")
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    printf 'not ok - %s\nexpected:\n%s\nactual:\n%s\n' \
      "${description}" "${expected}" "${actual}" >&2
    exit 1
  fi
  printf 'ok - %s\n' "${description}"
}

test_first_release() {
  local repo commit actual
  repo="$(new_repo v4.14.0)"
  commit="$(commit_state "${repo}" initial)"
  actual="$(resolve_tag "${repo}" "${commit}")"
  assert_equal $'tag=v4.14.0-ym.1\ncreate=true' "${actual}" \
    "first fork release starts at revision one"
}

test_legacy_migration() {
  local repo commit actual
  repo="$(new_repo v4.14.0)"
  commit="$(commit_state "${repo}" legacy-one)"
  git -C "${repo}" tag v4.14.0-ym "${commit}"
  commit="$(commit_state "${repo}" legacy-two)"
  git -C "${repo}" tag v4.14.0-ym2 "${commit}"
  commit="$(commit_state "${repo}" next)"
  actual="$(resolve_tag "${repo}" "${commit}")"
  assert_equal $'tag=v4.14.0-ym.3\ncreate=true' "${actual}" \
    "legacy fork tags migrate to canonical revision three"
}

test_canonical_increment() {
  local repo commit actual
  repo="$(new_repo v4.14.0)"
  commit="$(commit_state "${repo}" release-three)"
  git -C "${repo}" tag v4.14.0-ym.3 "${commit}"
  commit="$(commit_state "${repo}" next)"
  actual="$(resolve_tag "${repo}" "${commit}")"
  assert_equal $'tag=v4.14.0-ym.4\ncreate=true' "${actual}" \
    "canonical releases increment numerically"
}

test_upstream_reset() {
  local repo commit actual
  repo="$(new_repo v4.15.0)"
  commit="$(commit_state "${repo}" old-upstream)"
  git -C "${repo}" tag v4.14.0-ym.9 "${commit}"
  commit="$(commit_state "${repo}" new-upstream)"
  actual="$(resolve_tag "${repo}" "${commit}")"
  assert_equal $'tag=v4.15.0-ym.1\ncreate=true' "${actual}" \
    "new upstream versions reset the fork revision"
}

test_unrelated_tags_ignored() {
  local repo commit actual
  repo="$(new_repo v4.14.0)"
  commit="$(commit_state "${repo}" unrelated)"
  git -C "${repo}" tag v4.14.0-sm4 "${commit}"
  git -C "${repo}" tag v4.14.0-ym.bad "${commit}"
  git -C "${repo}" tag v4.13.0-ym.99 "${commit}"
  commit="$(commit_state "${repo}" next)"
  actual="$(resolve_tag "${repo}" "${commit}")"
  assert_equal $'tag=v4.14.0-ym.1\ncreate=true' "${actual}" \
    "unrelated and malformed tags do not affect releases"
}

test_already_released_commit() {
  local repo commit actual
  repo="$(new_repo v4.14.0)"
  commit="$(commit_state "${repo}" released)"
  git -C "${repo}" tag v4.14.0-ym.7 "${commit}"
  actual="$(resolve_tag "${repo}" "${commit}")"
  assert_equal $'tag=v4.14.0-ym.7\ncreate=false' "${actual}" \
    "an already released commit is idempotent"
}

test_invalid_upstream_version() {
  local repo commit
  repo="$(new_repo latest)"
  commit="$(commit_state "${repo}" invalid)"
  if resolve_tag "${repo}" "${commit}" >/dev/null 2>&1; then
    printf 'not ok - malformed upstream versions are rejected\n' >&2
    exit 1
  fi
  printf 'ok - malformed upstream versions are rejected\n'
}

test_tag_creator_http_contract() {
  local mock_dir args_file commit
  mock_dir="${TMP_ROOT}/mock-bin"
  args_file="${TMP_ROOT}/curl-args"
  commit="0123456789abcdef0123456789abcdef01234567"
  mkdir -p "${mock_dir}"

  cat > "${mock_dir}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output_file=""
printf '%s\n' "$@" > "${MOCK_ARGS_FILE}"
while (($# > 0)); do
  if [[ "$1" == "--output" ]]; then
    shift
    output_file="$1"
  fi
  shift
done
printf '{"message":"mock response"}\n' > "${output_file}"
printf '%s' "${MOCK_HTTP_STATUS}"
EOF
  chmod +x "${mock_dir}/curl"

  PATH="${mock_dir}:${PATH}" \
    MOCK_ARGS_FILE="${args_file}" \
    MOCK_HTTP_STATUS=201 \
    FORGEJO_API_URL=https://git.m0sh1.cc/api/v1 \
    FORGEJO_REPOSITORY=isityael/csi-driver-nfs \
    FORGEJO_TOKEN=test-token \
    "${TAG_CREATOR}" v4.14.0-ym.3 "${commit}"

  grep -Fx -- '--request' "${args_file}" >/dev/null
  grep -Fx -- 'POST' "${args_file}" >/dev/null
  grep -Fx -- 'Authorization: token test-token' "${args_file}" >/dev/null
  grep -Fx -- '{"tag_name":"v4.14.0-ym.3","target":"0123456789abcdef0123456789abcdef01234567"}' \
    "${args_file}" >/dev/null
  grep -Fx -- 'https://git.m0sh1.cc/api/v1/repos/isityael/csi-driver-nfs/tags' \
    "${args_file}" >/dev/null
  printf 'ok - tag creation uses the Forgejo repository API\n'

  if PATH="${mock_dir}:${PATH}" \
    MOCK_ARGS_FILE="${args_file}" \
    MOCK_HTTP_STATUS=409 \
    FORGEJO_API_URL=https://git.m0sh1.cc/api/v1 \
    FORGEJO_REPOSITORY=isityael/csi-driver-nfs \
    FORGEJO_TOKEN=test-token \
    "${TAG_CREATOR}" v4.14.0-ym.3 "${commit}" >/dev/null 2>&1; then
    printf 'not ok - immutable tag conflicts must fail\n' >&2
    exit 1
  fi
  printf 'ok - immutable tag conflicts fail safely\n'
}

test_private_image_auth_contract() {
  local auth_step build_step coverage_step
  auth_step='.jobs.build.steps[] | select(.name == "Authenticate to DHI")'
  build_step='.jobs.build.steps[] | select(.name == "Build container image")'
  coverage_step='.jobs.build.steps[] | select(.name == "Send coverage")'

  yq -e '.on.push.branches == ["isityael/dhi-hardening"]' \
    "${LINUX_WORKFLOW}" >/dev/null

  yq -e "${auth_step} | .[\"if\"] == \"github.event_name == 'push'\"" \
    "${LINUX_WORKFLOW}" >/dev/null
  yq -e "${auth_step} | .env.DHI_USERNAME == \"\${{ secrets.DHI_USERNAME }}\"" \
    "${LINUX_WORKFLOW}" >/dev/null
  yq -e "${auth_step} | .env.DHI_TOKEN == \"\${{ secrets.DHI_TOKEN }}\"" \
    "${LINUX_WORKFLOW}" >/dev/null
  yq -e "${auth_step} | .run | contains(\"docker login dhi.io\")" \
    "${LINUX_WORKFLOW}" >/dev/null
  yq -e "${build_step} | .[\"if\"] == \"github.event_name == 'push'\"" \
    "${LINUX_WORKFLOW}" >/dev/null
  yq -e "${build_step} | .run | contains(\"make container\")" \
    "${LINUX_WORKFLOW}" >/dev/null
  yq -e "${coverage_step} | .[\"if\"] == \"github.event_name == 'push'\"" \
    "${LINUX_WORKFLOW}" >/dev/null

  printf 'ok - private image builds authenticate only for trusted pushes\n'
}

test_dhi_platform_contract() {
  grep -Fx 'ALL_ARCH.linux = amd64' "${MAKEFILE}" >/dev/null
  grep -Fx 'ALL_OS_ARCH = linux-amd64' "${MAKEFILE}" >/dev/null

  if sed -n '/^container:/,/^\.PHONY: push/p' "${MAKEFILE}" | \
    grep -Eq 'binfmt|arm64|arm/v7|ppc64le'; then
    printf 'not ok - container builds include a non-amd64 platform\n' >&2
    exit 1
  fi

  printf 'ok - container builds target linux/amd64 only\n'
}

test_first_release
test_legacy_migration
test_canonical_increment
test_upstream_reset
test_unrelated_tags_ignored
test_already_released_commit
test_invalid_upstream_version
test_tag_creator_http_contract
test_private_image_auth_contract
test_dhi_platform_contract
