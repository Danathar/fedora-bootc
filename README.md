# fedora-bootc

Fedora bootc image built directly from a `Containerfile` and published to GHCR with GitHub Actions.

This repo is intentionally simpler than a BlueBuild-based image repo. There are no BlueBuild recipes or modules here. The image is defined by [`Containerfile`](./Containerfile), [`build_files/build.sh`](./build_files/build.sh), and the workflows in [`.github/workflows/`](./.github/workflows).

> [!NOTE]
> This is not an official Fedora, bootc, or Universal Blue image. It is a personal, opinionated image. Review the files in this repo before using it on real systems.

## Upstream Template

This repository started from the Universal Blue [`image-template`](https://github.com/ublue-os/image-template). The original template documentation is still useful background:

- [`ublue-os/image-template`](https://github.com/ublue-os/image-template)
- [Upstream `README.md`](https://github.com/ublue-os/image-template/blob/main/README.md)

## What This Repo Is

This image currently layers a few practical system-management changes on top of `quay.io/fedora/fedora-bootc`:

- Packages from [`build_files/build.sh`](./build_files/build.sh): `vim`, `btop`, `rpmconf`, `qemu-guest-agent`, Cockpit modules, and `tailscale`
- `sshd` enabled in the final image
- A `core` admin user created via [`build_files/core-user.conf`](./build_files/core-user.conf)
- An SSH `authorized_keys` file seeded from [`build_files/core-ssh.conf`](./build_files/core-ssh.conf)
- GitHub Actions publishing to `ghcr.io/<owner>/<repo>:latest`
- Local `just` helpers for OCI images, disk images, and quick VM boot tests

> [!WARNING]
> [`build_files/core-ssh.conf`](./build_files/core-ssh.conf) contains a placeholder key. Replace it or remove the `core` user / SSH provisioning before relying on it.

## How To Use It

### Use the published image

If you want to run the image from this repo as-is, switch an existing bootc host to:

```bash
sudo bootc switch ghcr.io/danathar/fedora-bootc:latest
sudo systemctl reboot
```

If you fork this repo, replace `danathar/fedora-bootc` with your own GHCR path.

### Use this repo as your own base

1. Fork the repo and enable GitHub Actions.
2. Edit [`Containerfile`](./Containerfile) if you want a different base image.
3. Edit [`build_files/build.sh`](./build_files/build.sh) for package and service changes.
4. Review or replace [`build_files/core-user.conf`](./build_files/core-user.conf) and [`build_files/core-ssh.conf`](./build_files/core-ssh.conf).
5. Create a Cosign key and add the private key as the `SIGNING_SECRET` repository secret if you want the default publish workflow to succeed on `main`.

```bash
COSIGN_PASSWORD="" cosign generate-key-pair
gh secret set SIGNING_SECRET < cosign.key
```

After that, push to `main`. [`.github/workflows/build.yml`](./.github/workflows/build.yml) builds directly from the `Containerfile`, pushes to GHCR, and signs the published tags.

If you do not want Cosign signing, remove or change the signing steps in [`.github/workflows/build.yml`](./.github/workflows/build.yml).

## Local Builds

This repo ships a [`Justfile`](./Justfile) for local OCI and disk-image builds.

Common commands:

```bash
IMAGE_NAME=fedora-bootc just build
IMAGE_NAME=fedora-bootc just build-qcow2
IMAGE_NAME=fedora-bootc just build-raw
IMAGE_NAME=fedora-bootc just run-vm-qcow2
```

Requirements:

- `podman`
- `just`
- `sudo` access for disk image builds
- a host with KVM if you want to boot the resulting VM locally

## Disk Images and ISOs

- [`disk_config/disk.toml`](./disk_config/disk.toml) is used for the qcow2 and raw image path.
- The repo currently includes [`disk_config/iso-gnome.toml`](./disk_config/iso-gnome.toml) and [`disk_config/iso-kde.toml`](./disk_config/iso-kde.toml) as ISO examples.
- Before using `just build-iso`, `just run-vm-iso`, or [`.github/workflows/build-disk.yml`](./.github/workflows/build-disk.yml), choose one of those ISO configs, copy it to `disk_config/iso.toml`, and change the embedded `bootc switch` target from `ghcr.io/ublue-os/image-template:latest` to your actual published image.
- [`.github/workflows/build-disk.yml`](./.github/workflows/build-disk.yml) is a manual workflow (`workflow_dispatch`) and can optionally upload artifacts to S3 if its secrets are configured.

## Repo Layout

- [`Containerfile`](./Containerfile): base image and final assembly
- [`build_files/build.sh`](./build_files/build.sh): package installation and system changes
- [`build_files/core-user.conf`](./build_files/core-user.conf): `core` user creation
- [`build_files/core-ssh.conf`](./build_files/core-ssh.conf): SSH key provisioning
- [`.github/workflows/build.yml`](./.github/workflows/build.yml): container build, push, and signing
- [`.github/workflows/build-disk.yml`](./.github/workflows/build-disk.yml): manual disk-image build workflow
- [`Justfile`](./Justfile): local build and VM helpers
- [`artifacthub-repo.yml`](./artifacthub-repo.yml): Artifact Hub metadata
- [`cosign.pub`](./cosign.pub): public key for verifying published images
