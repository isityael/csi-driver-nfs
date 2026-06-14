#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="${repo_root}/.ci/pre-commit/chart-version-bump.sh"
chart="charts/latest/csi-driver-nfs"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

setup_repo() {
  local workdir="$1"
  local version="${2:-v0.0.0}"

  git -C "$workdir" init -q
  git -C "$workdir" config user.email test@example.invalid
  git -C "$workdir" config user.name "Chart Version Test"

  mkdir -p "$workdir/${chart}/templates"
  cat >"$workdir/${chart}/Chart.yaml" <<YAML
apiVersion: v1
name: csi-driver-nfs
version: ${version}
YAML
  cat >"$workdir/${chart}/values.yaml" <<'YAML'
image:
  nfs:
    repository: ghcr.io/example/nfsplugin
    tag: "1.0.0"
YAML
  cat >"$workdir/${chart}/templates/controller.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: csi-driver-nfs
YAML

  git -C "$workdir" add "$chart"
  git -C "$workdir" commit -qm "Initial chart"
}

assert_version() {
  local workdir="$1"
  local want="$2"
  local got

  got="$(awk '/^version:/ {print $2}' "$workdir/${chart}/Chart.yaml")"
  [ "$got" = "$want" ] || fail "expected chart version ${want}, got ${got}"
}

assert_staged() {
  local workdir="$1"
  local path="$2"

  git -C "$workdir" diff --cached --name-only | grep -qx "$path" || fail "expected ${path} to be staged"
}

test_values_change_bumps_chart_version() {
  local workdir="${tmpdir}/values-change"
  mkdir -p "$workdir"
  setup_repo "$workdir"

  sed -i.bak 's/1.0.0/1.0.1/' "$workdir/${chart}/values.yaml"
  rm "$workdir/${chart}/values.yaml.bak"
  git -C "$workdir" add "${chart}/values.yaml"

  (cd "$workdir" && "$script")

  assert_version "$workdir" "v0.0.1"
  assert_staged "$workdir" "${chart}/Chart.yaml"
}

test_template_change_bumps_chart_version() {
  local workdir="${tmpdir}/template-change"
  mkdir -p "$workdir"
  setup_repo "$workdir"

  printf '\n  labels:\n    app: csi-driver-nfs\n' >>"$workdir/${chart}/templates/controller.yaml"
  git -C "$workdir" add "${chart}/templates/controller.yaml"

  (cd "$workdir" && "$script")

  assert_version "$workdir" "v0.0.1"
  assert_staged "$workdir" "${chart}/Chart.yaml"
}

test_existing_chart_version_change_is_not_bumped_again() {
  local workdir="${tmpdir}/already-bumped"
  mkdir -p "$workdir"
  setup_repo "$workdir"

  sed -i.bak 's/1.0.0/1.0.1/' "$workdir/${chart}/values.yaml"
  rm "$workdir/${chart}/values.yaml.bak"
  sed -i.bak 's/version: v0.0.0/version: v0.0.9/' "$workdir/${chart}/Chart.yaml"
  rm "$workdir/${chart}/Chart.yaml.bak"
  git -C "$workdir" add "${chart}/values.yaml" "${chart}/Chart.yaml"

  (cd "$workdir" && "$script")

  assert_version "$workdir" "v0.0.9"
  assert_staged "$workdir" "${chart}/Chart.yaml"
}

test_values_change_bumps_chart_version
test_template_change_bumps_chart_version
test_existing_chart_version_change_is_not_bumped_again

echo "chart-version-bump tests passed"
