# Automatic Fork Release Design

## Goal

Automatically create a new fork release after the Linux build succeeds on the
default `isityael/dhi-hardening` branch, publish the corresponding NFS CSI image
to `ghcr.io/isityael/nfsplugin`, and allow ArgoCD Image Updater to select and
deploy the new immutable version through GitOps.

## Release version contract

Fork releases use this canonical tag format:

```text
v<upstream-version>-ym.<revision>
```

For the current upstream version, the next tag is `v4.14.0-ym.3`. The existing
legacy tags `v4.14.0-ym` and `v4.14.0-ym2` are treated as revisions 1 and 2 only
for migration purposes. Subsequent releases are `v4.14.0-ym.4`,
`v4.14.0-ym.5`, and so on. When the upstream application version changes, the
fork revision resets to 1, for example `v4.15.0-ym.1`.

The upstream version is derived from the checked-in Helm chart application
version rather than from the previous Git tag. The calculation accepts only
tags belonging to the same upstream version and matching the canonical fork
namespace.

## Promotion workflow

The existing Linux workflow in
`/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/.github/workflows/linux.yaml` remains
the build gate. A promotion job is added after its `build` job and runs only for
a successful push to `isityael/dhi-hardening`; pull requests and other branches
cannot create releases.

The promotion job checks out the complete tag history, invokes a repository
script to calculate the next tag, and creates the tag at the exact workflow
commit through the Forgejo API. It authenticates with the short-lived automatic
Forgejo workflow token and therefore introduces no permanent repository-write
secret. The request is idempotent: a matching tag already pointing at the
commit is success, while a conflicting tag or concurrent release is detected
and cannot silently move an existing tag.

The version calculation is implemented as a standalone testable script under
`/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/hack/`. Tests cover an empty release
history, migration from the two legacy tags, normal revision increments,
upstream-version changes, unrelated tags, repeat execution for an already
released commit, and concurrent tag conflicts.

## Image publication

Creating the `v*` Git tag triggers the existing Woodpecker release workflow in
`/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/.woodpecker/release.yaml`. That
workflow continues to own the multi-stage release build, GHCR publication,
Trivy scan, and Cosign signature. It publishes the canonical Git tag as an
immutable image tag, for example:

```text
ghcr.io/isityael/nfsplugin:v4.14.0-ym.3
```

If publication fails, ArgoCD Image Updater cannot select the missing image. The
existing release pipeline can be retried without minting another Git tag.

## GitOps deployment

The ArgoCD Application manifest at
`/Users/yaelmeya/git/m0sh1.cc/infra/argocd/apps/cluster/nfs-csi.yaml` is annotated
for `ghcr.io/isityael/nfsplugin`. Image discovery is restricted to canonical
`v<upstream>-ym.<revision>` tags and uses semantic-version ordering with an
explicit prerelease-compatible constraint.

Image Updater uses Git write-back. It commits the selected Helm parameter
override to the infrastructure repository; it does not write directly to the
cluster. ArgoCD then reconciles that Git commit through the existing automated
sync policy. The checked-in wrapper values remain the recovery baseline while
the generated ArgoCD source override records the deployed image version.

## Security and failure handling

- Pull-request workflows have no release-write path.
- No registry or Forgejo credentials are added to Git.
- Existing tags are immutable and are never force-updated.
- A failed build creates no tag.
- A failed image publication creates no deployable GHCR version.
- Image Updater accepts only the fork's canonical release-tag namespace.
- Cluster changes flow only through Git and ArgoCD.

## Verification

Verification includes the release-version unit tests, workflow syntax checks,
a successful Linux build with the promotion job skipped outside the default
branch, a controlled default-branch promotion producing exactly one tag, a
successful Woodpecker release for that tag, confirmation of the signed GHCR
image, an Image Updater Git write-back, and ArgoCD synchronization to the exact
published image digest.
