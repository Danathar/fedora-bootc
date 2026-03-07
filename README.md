# fedora-bootc

This repository builds a custom Fedora bootc image and publishes it to GitHub Container Registry (GHCR).

If you are new to bootc, the short version is: your operating system is built and shipped as an OCI image (the same packaging format used for container images), and `bootc switch` lets a machine move to that image on the next reboot. This repo defines that image with a `Containerfile`, a few helper files, and GitHub Actions workflows.

> [!NOTE]
> This is a personal, opinionated image. It is not an official Fedora, bootc, or Universal Blue image. This repo started from the Universal Blue [`image-template`](https://github.com/ublue-os/image-template), and some AI assistance was used while adapting that template into this Fedora-bootc-focused repo. Review the files here before using it on real systems.

## What This Repo Builds

The base image is [`quay.io/fedora/fedora-bootc`](https://quay.io/repository/fedora/fedora-bootc). On top of that base, this repo currently:

- installs `vim`, `btop`, and `rpmconf` for day-to-day admin work
- installs `qemu-guest-agent` so the image behaves better inside VMs
- installs `cockpit`, `cockpit-podman`, `cockpit-ostree`, `cockpit-selinux`, and `cockpit-storaged` for browser-based management
- installs `tailscale`
- enables `sshd`
- can optionally create a `core` user with `wheel` access
- can optionally seed `/home/core/.ssh/authorized_keys` from a build-time public key

By default, the image does not include a personal SSH key and does not create the optional `core` user unless you opt in at build time.

## If You Just Want To Use The Image

The published image for this repo is:

```text
ghcr.io/danathar/fedora-bootc:latest
```

To move an existing bootc-capable Fedora host to that image:

```bash
sudo bootc switch ghcr.io/danathar/fedora-bootc:latest
sudo systemctl reboot
```

After the reboot, `bootc status` should show the new image as the booted deployment.

## If You Want To Customize Or Fork It

This repo is intentionally small. The important files are:

- [`Containerfile`](./Containerfile): chooses the base image and defines the final image layout
- [`build_files/build.sh`](./build_files/build.sh): installs packages and enables services
- [`build_files/core-user.conf.example`](./build_files/core-user.conf.example): example sysusers file for the optional `core` user
- [`build_files/core-ssh.conf.example`](./build_files/core-ssh.conf.example): example tmpfiles entry for the optional SSH key
- [`.github/workflows/build.yml`](./.github/workflows/build.yml): builds the OCI image and pushes it to GHCR
- [`.github/workflows/build-disk.yml`](./.github/workflows/build-disk.yml): builds disk artifacts such as qcow2 and a generic installer ISO
- [`Justfile`](./Justfile): local helper commands for building and testing

If you fork the repo, the usual edit points are:

1. change the base image in [`Containerfile`](./Containerfile) if you want to build from something other than Fedora bootc
2. change package or service choices in [`build_files/build.sh`](./build_files/build.sh)
3. decide whether you want the optional `core` user at all, or whether you want a different user-management pattern entirely
4. adjust metadata in [`.github/workflows/build.yml`](./.github/workflows/build.yml) so GHCR labels describe your image instead of this one

## Optional `core` User And SSH Key Injection

This repo is designed so you can use your own public key without committing it to git.

Build-time controls:

- `CORE_SSH_PUBLIC_KEY=...`: inject a one-line SSH public key into `/home/core/.ssh/authorized_keys`
- `ENABLE_CORE_USER=true`: create the optional `core` user even if you are not injecting a key

If `CORE_SSH_PUBLIC_KEY` is set, the build automatically enables the `core` user as well.

### Local builds

To build a local image with your SSH key baked in:

```bash
CORE_SSH_PUBLIC_KEY="$(tr -d '\n' < ~/.ssh/id_ed25519.pub)" \
just build
```

If you only want the user without an injected key:

```bash
ENABLE_CORE_USER=true just build
```

### GitHub Actions builds

For repo builds on GitHub, use Actions variables rather than editing tracked files. A public key is not secret material, so a repository variable is the right default.

Recommended repository variables:

- `CORE_SSH_PUBLIC_KEY`: your one-line public key
- `ENABLE_CORE_USER`: optional; only needed if you want the `core` user even when no key is injected

Using the GitHub CLI:

```bash
gh variable set CORE_SSH_PUBLIC_KEY --body "$(tr -d '\n' < ~/.ssh/id_ed25519.pub)"
```

Only set `ENABLE_CORE_USER` if you want the `core` user without also injecting a key:

```bash
gh variable set ENABLE_CORE_USER --body true
```

Using the GitHub web UI:

1. go to `Settings`
2. open `Secrets and variables` -> `Actions`
3. choose `Variables`
4. add `CORE_SSH_PUBLIC_KEY`
5. optionally add `ENABLE_CORE_USER` with the value `true` if you want the user even without an injected key

Once those variables are set, the normal build workflow will pass them into the image build. The published container image and any disk images built from it will then include the optional `core` account and key.

## How GitHub Builds Work

The main image workflow is [`.github/workflows/build.yml`](./.github/workflows/build.yml).

What it does:

- builds the OCI image from [`Containerfile`](./Containerfile)
- tags it as `latest`, `latest.YYYYMMDD`, and `YYYYMMDD`
- pushes those tags to `ghcr.io/<owner>/<repo>` when changes land on the default branch
- skips doc-only changes so README edits do not burn runner time

Signing is optional:

- if the repository secret `SIGNING_SECRET` is present, the workflow signs published images with Cosign
- if the secret is absent, the workflow still builds and publishes the image, it simply skips signing

If you want signing enabled, generate a key pair and add the private key to GitHub Actions secrets:

```bash
COSIGN_PASSWORD="" cosign generate-key-pair
gh secret set SIGNING_SECRET < cosign.key
```

The public half of the key is stored in [`cosign.pub`](./cosign.pub).

## Local Builds

The [`Justfile`](./Justfile) is the local entry point. A few environment variables control its defaults:

- `IMAGE_NAME`: local image name, defaults to `fedora-bootc`
- `DEFAULT_TAG`: local image tag, defaults to `latest`
- `BIB_IMAGE`: the bootc-image-builder container image used for local disk builds
- `ISO_CONFIG`: which installer ISO config file to use, defaults to `disk_config/iso.toml`
- `ENABLE_CORE_USER`: whether to create the optional `core` user during local builds
- `CORE_SSH_PUBLIC_KEY`: one-line SSH public key to inject for the optional `core` user

Common commands:

```bash
just build
just build-qcow2
just build-raw
just build-iso
just run-vm-qcow2
```

What those mean:

- `just build` builds the OCI image locally with Podman
- `just build-qcow2` and `just build-raw` turn that OCI image into bootable disk artifacts
- `just build-iso` builds a generic installer ISO using the TOML selected by `ISO_CONFIG`
- `just run-vm-qcow2` boots the generated qcow2 artifact inside a qemu container so you can smoke-test it quickly

## Disk Images And Installer Profiles

This repo ships two kinds of disk config:

- [`disk_config/disk.toml`](./disk_config/disk.toml): settings used for raw and qcow2 disk images
- [`disk_config/iso.toml`](./disk_config/iso.toml): the generic installer ISO profile used by local helpers and the GitHub Actions disk-image workflow

This repo does not ship GNOME- or KDE-specific installer variants. The target image is not a desktop image, so the installer side stays generic as well. If you want to experiment with a custom installer profile of your own, create another TOML file and point `ISO_CONFIG` at it locally:

```bash
ISO_CONFIG=disk_config/my-installer.toml just build-iso
```

The disk-image workflow is manual by default for publishing. It can optionally upload artifacts to S3 if the S3-related repository secrets are configured.

## A Quick Tour Of The Repo

If you are reading the code to learn how this works, follow it in this order:

1. start with [`Containerfile`](./Containerfile)
2. then read [`build_files/build.sh`](./build_files/build.sh)
3. then read [`.github/workflows/build.yml`](./.github/workflows/build.yml)
4. then read [`Justfile`](./Justfile) if you want local build and VM helpers
5. finally read [`.github/workflows/build-disk.yml`](./.github/workflows/build-disk.yml) if you want disk artifacts in CI

That path mirrors the actual flow:

- `Containerfile` defines the image
- GitHub Actions publishes it
- `Justfile` and the disk workflow turn it into bootable artifacts
