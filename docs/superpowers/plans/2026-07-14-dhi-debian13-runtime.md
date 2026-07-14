# DHI Debian 13 Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate both NFS CSI plugin image build paths to a digest-pinned DHI Debian 13 base while retaining all runtime mount requirements.

**Architecture:** Keep the existing single runtime stage in `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/Dockerfile` and the existing Go builder plus runtime stages in `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/Dockerfile.release`. Replace only the runtime base and its package-install layer so both publication paths remain equivalent.

**Tech Stack:** Dockerfile, Docker BuildKit/buildx, Docker Hardened Images, Debian 13 apt.

## Global Constraints

- Use `dhi.io/debian-base:trixie-debian13-dev@sha256:712ec3f1c4627b16cdaec6bff3750bcbd84eb9082f2c9f6cd382bc1101abcde0` in both runtime stages.
- Preserve root execution, `/nfsplugin`, and the existing package set.
- Do not change charts, deployment manifests, CI publication targets, or cluster resources.
- Remove package indexes in the package-install layer.

---

### Task 1: Migrate both runtime stages

**Files:**
- Modify: `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/Dockerfile`
- Modify: `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/Dockerfile.release`

**Interfaces:**
- Consumes: DHI multi-architecture Debian 13 development image and Debian package repositories.
- Produces: equivalent local/upstream and Woodpecker release runtime stages.

- [x] **Step 1: Run the failing content assertion**

```bash
for file in Dockerfile Dockerfile.release; do
  grep -Fq 'FROM dhi.io/debian-base:trixie-debian13-dev@sha256:712ec3f1c4627b16cdaec6bff3750bcbd84eb9082f2c9f6cd382bc1101abcde0' "$file"
done
```

Expected: non-zero exit because both Dockerfiles still use `registry.k8s.io/build-image/debian-base`.

- [x] **Step 2: Replace the runtime base and package layer**

Use this runtime base in both Dockerfiles:

```dockerfile
FROM dhi.io/debian-base:trixie-debian13-dev@sha256:712ec3f1c4627b16cdaec6bff3750bcbd84eb9082f2c9f6cd382bc1101abcde0
```

Use this package installation in both Dockerfiles:

```dockerfile
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates mount netbase nfs-common && \
    rm -rf /var/lib/apt/lists/*
```

- [x] **Step 3: Run content checks**

```bash
for file in Dockerfile Dockerfile.release; do
  grep -Fq 'FROM dhi.io/debian-base:trixie-debian13-dev@sha256:712ec3f1c4627b16cdaec6bff3750bcbd84eb9082f2c9f6cd382bc1101abcde0' "$file"
  grep -Fq 'apt-get install -y --no-install-recommends ca-certificates mount netbase nfs-common' "$file"
  ! grep -Eq 'clean-install|apt upgrade|apt-mark unhold|registry.k8s.io/build-image/debian-base' "$file"
done
```

Expected: exit 0.

- [x] **Step 4: Build the release image**

```bash
docker build --file Dockerfile.release --tag csi-driver-nfs:dhi-debian13-test .
```

Expected: exit 0 with the Go binary and Debian packages installed.

- [x] **Step 5: Inspect runtime behavior**

```bash
test "$(docker image inspect --format '{{.Config.User}}' csi-driver-nfs:dhi-debian13-test)" = "0"
test "$(docker image inspect --format '{{json .Config.Entrypoint}}' csi-driver-nfs:dhi-debian13-test)" = '["/nfsplugin"]'
docker run --rm --entrypoint /bin/sh csi-driver-nfs:dhi-debian13-test -c '
  set -eu
  test "$(id -u)" = 0
  command -v mount
  command -v mount.nfs
  dpkg-query -W ca-certificates mount netbase nfs-common
  test -z "$(find /var/lib/apt/lists -mindepth 1 -print -quit)"
'
```

Expected: exit 0 and paths for `mount` and `mount.nfs`.

- [x] **Step 6: Review the final diff**

```bash
git diff --check
git diff -- Dockerfile Dockerfile.release docs/superpowers/specs/2026-07-14-dhi-debian13-runtime-design.md docs/superpowers/plans/2026-07-14-dhi-debian13-runtime.md
```

Expected: no whitespace errors and only the approved DHI migration plus its design and plan documents.
