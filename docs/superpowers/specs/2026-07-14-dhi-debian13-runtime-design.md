# DHI Debian 13 Runtime Design

## Goal

Replace the Kubernetes Debian 12 build image used by the NFS CSI plugin with the current Docker Hardened Images Debian 13 development base while preserving the plugin's root execution and NFS mount-tool contract.

## Scope

Update both image build paths:

- `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/Dockerfile`
- `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/Dockerfile.release`

No chart, deployment manifest, CI publication target, or cluster resource changes are required.

## Image and package policy

Both Dockerfiles use the same multi-architecture base reference:

```dockerfile
dhi.io/debian-base:trixie-debian13-dev@sha256:712ec3f1c4627b16cdaec6bff3750bcbd84eb9082f2c9f6cd382bc1101abcde0
```

The `-dev` variant is intentional because the final CSI runtime requires Debian's `mount` and `nfs-common` packages and must run as root for filesystem mount operations. Package installation uses `apt-get install --no-install-recommends`; it does not run a general distribution upgrade. Apt indexes are removed in the same layer.

## Compatibility requirements

The resulting image must:

- support `linux/amd64` and `linux/arm64` through the pinned OCI index;
- retain `/nfsplugin` as its entrypoint;
- run as UID 0;
- provide `mount` and `mount.nfs`;
- install `ca-certificates`, `mount`, `nfs-common`, and `netbase`;
- contain no retained `/var/lib/apt/lists` package indexes.

## Verification

A pre-change content assertion must fail against the old base image. After the edit, content assertions must confirm both Dockerfiles use the same DHI reference and no longer use `clean-install`, `apt upgrade`, or `apt-mark unhold`. Build `/Users/yaelmeya/git/m0sh1.cc/csi-driver-nfs/Dockerfile.release` for the local architecture and inspect the image for the required user, entrypoint, tools, packages, and apt-index cleanup.
