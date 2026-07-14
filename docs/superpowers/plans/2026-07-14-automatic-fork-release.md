# Automatic Fork Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tag each successful default-branch Linux build with the next `v<upstream>-ym.<revision>` version, publish that tag to GHCR, and deploy it through ArgoCD Image Updater.

**Architecture:** Bash helpers read the canonical Makefile version, calculate an idempotent release, and create an immutable tag through Forgejo's short-lived workflow token. The existing Linux workflow gates promotion, Woodpecker publishes and signs tag builds, and the infrastructure repository's active `ImageUpdater` CR writes an ArgoCD source override back to Git.

**Tech Stack:** Bash, Git, Forgejo Actions and REST API, Woodpecker, GHCR, Helm, ArgoCD Image Updater.

## Global Constraints

- The migration sequence is `v4.14.0-ym`, `v4.14.0-ym2`, then `v4.14.0-ym.3`.
- A new upstream value from `IMAGE_VERSION ?=` in `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/Makefile` resets the revision to `.1`.
- Only a successful push build on `isityael/dhi-hardening` may create a release; pull requests have no write path.
- Tags are immutable. Publication remains owned by `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/.woodpecker/release.yaml`.
- Deployment is Git to Image Updater to ArgoCD to Kubernetes. No imperative Kubernetes writes.
- Preserve unrelated dirty and untracked files in both repositories.

## File Structure

- `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/hack/next-fork-tag.sh`: calculate `tag=<value>` and `create=<true|false>`.
- `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/hack/create-forgejo-tag.sh`: create a tag with the Forgejo API and reject conflicts.
- `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/hack/test-automatic-release.sh`: isolated Git and mocked-HTTP tests.
- `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/hack/verify-all.sh`: run the new tests in the normal verification gate.
- `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/.github/workflows/linux.yaml`: promote after the successful build.
- `/Users/yaelmeya/git/m0sh1.cc/infra/argocd/apps/cluster/nfs-csi.yaml`: compatibility annotations.
- `/Users/yaelmeya/git/m0sh1.cc/infra/apps/cluster/argocd-image-updater/templates/image-updater-ghcr-apps.yaml`: active NFS CSI image inventory.
- `/Users/yaelmeya/git/m0sh1.cc/infra/apps/cluster/argocd-image-updater/Chart.yaml`: wrapper behavior-version bump.

---

### Task 1: Test and implement release calculation

**Files:** Create `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/hack/next-fork-tag.sh` and `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/hack/test-automatic-release.sh`; modify `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/hack/verify-all.sh`.

**Interfaces:** Consume an optional commit argument (default `HEAD`) in a Git repository with `IMAGE_VERSION ?= vX.Y.Z`; emit exactly `tag=<tag>` and `create=<true|false>`.

- [ ] Write failing temporary-repository tests for: no tags gives `.1`; legacy `-ym` plus `-ym2` gives `.3`; canonical `.3` gives `.4`; `IMAGE_VERSION ?= v4.15.0` ignores v4.14 tags and gives `.1`; malformed and `-sm` tags are ignored; a canonical tag already pointing at the commit returns `create=false`; malformed Makefile versions fail.
- [ ] Run `cd /Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs && bash hack/test-automatic-release.sh`; expect failure because the resolver is absent.
- [ ] Implement strict Bash parsing with `awk '$1 == "IMAGE_VERSION" && $2 == "?=" { print $3; exit }' Makefile`, validate `^v[0-9]+\.[0-9]+\.[0-9]+$`, map only `-ym` to revision 1, `-ym2` to revision 2, and `-ym.N` to numeric N, use base-10 arithmetic, and validate the commit using `git rev-parse --verify "${commit}^{commit}"`.
- [ ] Append `${PKG_ROOT}/hack/test-automatic-release.sh` to `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/hack/verify-all.sh`.
- [ ] Run `bash hack/test-automatic-release.sh` and `shellcheck hack/next-fork-tag.sh hack/test-automatic-release.sh`; expect all tests and ShellCheck to pass.
- [ ] Commit only those three files with `git commit -m "ci: calculate automatic fork release tags"`.

### Task 2: Test and implement safe Forgejo promotion

**Files:** Create `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/hack/create-forgejo-tag.sh`; modify `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/hack/test-automatic-release.sh` and `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/.github/workflows/linux.yaml`.

**Interfaces:** Consume `FORGEJO_API_URL`, `FORGEJO_REPOSITORY`, `FORGEJO_TOKEN`, a canonical tag, and a 40-character commit; HTTP 201 is success, 409 is an immutable conflict, and every other status fails.

- [ ] Add a fake curl client to the test script. Assert a 201 response succeeds, a 409 response fails, and the request contains `POST`, `/repos/isityael/csi-driver-nfs/tags`, an authorization header, and `{"tag_name":"v4.14.0-ym.3","target":"<sha>"}`.
- [ ] Run `bash hack/test-automatic-release.sh`; expect failure because the creator is absent.
- [ ] Implement the creator using a temporary response file and `curl --silent --show-error --output "$response_file" --write-out '%{http_code}' --request POST --header "Authorization: token ${FORGEJO_TOKEN}" --header 'Content-Type: application/json' --data "$payload" "${FORGEJO_API_URL}/repos/${FORGEJO_REPOSITORY}/tags"`. Validate inputs before the request, never print the token, accept only 201, and report 409 as an immutable conflict.
- [ ] Add a `promote` job to `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/.github/workflows/linux.yaml` with `needs: build`, `runs-on: ubuntu-latest`, and `if: forgejo.event_name == 'push' && forgejo.ref == 'refs/heads/isityael/dhi-hardening'`. Checkout with `fetch-depth: 0` and `persist-credentials: false`; append resolver output to `${GITHUB_OUTPUT}`; call the creator only when `steps.release.outputs.create == 'true'` using `${{ forgejo.api_url }}`, `${{ forgejo.repository }}`, and `${{ secrets.FORGEJO_TOKEN }}`.
- [ ] Run `bash hack/test-automatic-release.sh`, `shellcheck hack/next-fork-tag.sh hack/create-forgejo-tag.sh hack/test-automatic-release.sh`, and `yamllint .github/workflows/linux.yaml`; expect success.
- [ ] Commit the three files with `git commit -m "ci: tag successful fork builds"`.

### Task 3: Test and implement GitOps image deployment

**Files:** Modify `/Users/yaelmeya/git/m0sh1.cc/infra/argocd/apps/cluster/nfs-csi.yaml`, `/Users/yaelmeya/git/m0sh1.cc/infra/apps/cluster/argocd-image-updater/templates/image-updater-ghcr-apps.yaml`, and `/Users/yaelmeya/git/m0sh1.cc/infra/apps/cluster/argocd-image-updater/Chart.yaml`.

**Interfaces:** Consume signed `v4.X.Y-ym.N` tags and produce Git-authored Helm overrides for `csi-driver-nfs.image.nfs.repository` and `csi-driver-nfs.image.nfs.tag`.

- [ ] Render the current wrapper with `helm template argocd-image-updater /Users/yaelmeya/git/m0sh1.cc/infra/apps/cluster/argocd-image-updater | yq 'select(.kind == "ImageUpdater") | .spec.applicationRefs[] | select(.namePattern == "nfs-csi")'`; expect no output.
- [ ] Add annotations to `/Users/yaelmeya/git/m0sh1.cc/infra/argocd/apps/cluster/nfs-csi.yaml`: image list `nfs=ghcr.io/isityael/nfsplugin:4.x-0`, strategy `semver`, allow-tags `regexp:^v4\.[0-9]+\.[0-9]+-ym\.[1-9][0-9]*$`, the two Helm paths above, and Git write-back.
- [ ] Add an `nfs-csi` entry to the active GHCR `ImageUpdater` CR. Override write-back to `method: "git:repocreds"`, branch `main`, and exact generated target `apps/cluster/nfs-csi/.argocd-source-nfs-csi.yaml`; set `imageName: "ghcr.io/isityael/nfsplugin:4.x-0"`; use `updateStrategy: "semver"`, `forceUpdate: true`, canonical allow-tags, and the two Helm manifest targets.
- [ ] Change `version: 0.2.58` to `version: 0.2.59` in `/Users/yaelmeya/git/m0sh1.cc/infra/apps/cluster/argocd-image-updater/Chart.yaml`.
- [ ] Render again and assert exactly one `nfs-csi` entry with the expected selector, write-back target, and Helm paths. Run `mise run policy` and `mise run k8s:lint-changed`; expect success.
- [ ] Commit only the three infrastructure files with `git commit -m "feat(nfs-csi): automate fork image updates"`.

### Task 4: Publish, reconcile, and verify

**Files:** Update or create Basic Memory project `main` note `projects/CSI Driver NFS Automatic Fork Releases.md` after verification.

- [ ] Run the release tests, ShellCheck, YAML validation, `git diff --check`, `mise run policy`, and `mise run k8s:lint-changed` once more from clean committed states.
- [ ] Push `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs` branch `isityael/dhi-hardening` and `/Users/yaelmeya/git/m0sh1.cc/infra` branch `main` without force.
- [ ] With `fj` and `woodpecker-cli`, verify the Forgejo build succeeds, promotion creates exactly `v4.14.0-ym.3`, and the Woodpecker tag pipeline publishes and signs `ghcr.io/isityael/nfsplugin:v4.14.0-ym.3`. Rerunning the same commit must not mint another tag.
- [ ] Run only `argocd app sync argocd-image-updater`, `argocd app wait argocd-image-updater --health --sync`, `argocd app get nfs-csi`, and read-only `kubectl get` commands. Verify the Image Updater Git commit, ArgoCD `Synced/Healthy`, and the exact deployed GHCR digest.
- [ ] Search Basic Memory before writing. Record the version source and migration, Forgejo-to-Woodpecker chain, ImageUpdater CR ownership, exact generated-source write-back path, verification commands, and immutable-conflict recovery.
