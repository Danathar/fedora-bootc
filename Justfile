# Default values for local builds. Override them with environment variables
# when testing forks, alternate tags, your own installer profile, or optional
# SSH access settings.

export image_name := env("IMAGE_NAME", "fedora-bootc")
export default_tag := env("DEFAULT_TAG", "latest")

# Keep local disk-image builds on the same bootc-image-builder image as CI.

export bib_image := env("BIB_IMAGE", "ghcr.io/lorbuschris/bootc-image-builder:20250608")

# ISO helpers default to the repo's generic installer profile.

export iso_config := env("ISO_CONFIG", "disk_config/iso.toml")

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# Check every Justfile in the repo without rewriting it.
[group('Just')]
check:
    #!/usr/bin/env bash
    set -euo pipefail

    find . -type f -name "*.just" | while read -r file; do
        echo "Checking syntax: $file"
        just --unstable --fmt --check -f "$file"
    done

    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Apply the canonical formatter to every Justfile in the repo.
[group('Just')]
fix:
    #!/usr/bin/env bash
    set -euo pipefail

    find . -type f -name "*.just" | while read -r file; do
        echo "Formatting: $file"
        just --unstable --fmt -f "$file"
    done

    echo "Formatting: Justfile"
    just --unstable --fmt -f Justfile

# Remove generated build output so the next build starts cleanly.
[group('Utility')]
clean:
    #!/usr/bin/env bash
    set -euo pipefail

    rm -rf _build _build-* _build_* output out .tmp previous.manifest.json changelog.md output.env

# Convenience wrapper for the clean target when root-owned artifacts exist.
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# Run a command as root when needed while still working in non-root shells.
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/env bash
    set -euo pipefail

    sudoif() {
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif command -v sudo >/dev/null 2>&1; then
            if [[ -n "${SSH_ASKPASS:-}" && ( -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ) ]]; then
                /usr/bin/sudo --askpass "$@"
            else
                /usr/bin/sudo "$@"
            fi
        else
            echo "sudo is required for this command" >&2
            exit 1
        fi
    }

    sudoif {{ command }} {{ args }}

# Build the OCI image defined by Containerfile.
# Set ENABLE_CORE_USER=true and/or CORE_SSH_PUBLIC_KEY in your shell if you want
# the image to create the optional core account.

# Example: CORE_SSH_PUBLIC_KEY="$(tr -d '\n' < ~/.ssh/id_ed25519.pub)" just build
build target_image=image_name tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail

    enable_core_user="${ENABLE_CORE_USER:-false}"
    core_ssh_public_key="${CORE_SSH_PUBLIC_KEY:-}"

    podman build \
        --build-arg "ENABLE_CORE_USER=${enable_core_user}" \
        --build-arg "CORE_SSH_PUBLIC_KEY=${core_ssh_public_key}" \
        --pull=newer \
        --tag "${target_image}:${tag}" \
        .

# Ensure the target image is present in rootful podman storage before calling
# bootc-image-builder. bootc-image-builder runs privileged and reads from the

# rootful container store, not the rootless one.
[private]
_rootful_load_image target_image=image_name tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail

    target_ref="${target_image}:${tag}"
    if just sudoif podman image exists "${target_ref}" >/dev/null 2>&1; then
        echo "Rootful podman already has ${target_ref}"
        exit 0
    fi

    if podman image exists "${target_ref}" >/dev/null 2>&1 && [[ -z "${SUDO_USER:-}" && "${UID}" -ne 0 ]]; then
        copytmp=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
        just sudoif env "TMPDIR=${copytmp}" podman image scp \
            "${UID}@localhost::${target_ref}" \
            "root@localhost::${target_ref}"
        rm -rf "${copytmp}"
        exit 0
    fi

    echo "Pulling ${target_ref} into rootful podman"
    just sudoif podman pull "${target_ref}"

# Convert an OCI image into a bootable artifact with bootc-image-builder.
[private]
_build-bib target_image tag image_type config: (_rootful_load_image target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail

    args=(--type "${image_type}" --use-librepo=True --rootfs=btrfs)
    buildtmp=$(mktemp -p "${PWD}" -d -t _build-bib.XXXXXXXXXX)

    sudo podman run \
        --rm \
        -it \
        --privileged \
        --pull=newer \
        --net=host \
        --security-opt label=type:unconfined_t \
        -v "${PWD}/${config}:/config.toml:ro" \
        -v "${buildtmp}:/output" \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        "${bib_image}" \
        "${args[@]}" \
        "${target_image}:${tag}"

    mkdir -p output
    sudo mv -f "${buildtmp}"/* output/
    sudo rmdir "${buildtmp}"
    sudo chown -R "${USER}:${USER}" output/

# Rebuild the OCI image first, then convert it into a bootable artifact.
[private]
_rebuild-bib target_image tag image_type config: (build target_image tag) && (_build-bib target_image tag image_type config)

[group('Build Virtual Machine Image')]
build-qcow2 target_image=("localhost/" + image_name) tag=default_tag: && (_build-bib target_image tag "qcow2" "disk_config/disk.toml")

[group('Build Virtual Machine Image')]
build-raw target_image=("localhost/" + image_name) tag=default_tag: && (_build-bib target_image tag "raw" "disk_config/disk.toml")

[group('Build Virtual Machine Image')]
build-iso target_image=("localhost/" + image_name) tag=default_tag: && (_build-bib target_image tag "iso" iso_config)

[group('Build Virtual Machine Image')]
rebuild-qcow2 target_image=("localhost/" + image_name) tag=default_tag: && (_rebuild-bib target_image tag "qcow2" "disk_config/disk.toml")

[group('Build Virtual Machine Image')]
rebuild-raw target_image=("localhost/" + image_name) tag=default_tag: && (_rebuild-bib target_image tag "raw" "disk_config/disk.toml")

[group('Build Virtual Machine Image')]
rebuild-iso target_image=("localhost/" + image_name) tag=default_tag: && (_rebuild-bib target_image tag "iso" iso_config)

# Boot the generated artifact inside a qemu container for a quick smoke test.
[private]
_run-vm target_image tag image_type:
    #!/usr/bin/env bash
    set -euo pipefail

    image_file="output/${image_type}/disk.${image_type}"
    if [[ "${image_type}" == "iso" ]]; then
        image_file="output/bootiso/install.iso"
    fi

    if [[ ! -f "${image_file}" ]]; then
        just "build-${image_type}" "${target_image}" "${tag}"
    fi

    port=8006
    while ss -tunal | grep -q ":${port}"; do
        port=$((port + 1))
    done

    echo "Using port: ${port}"
    echo "Connect to http://localhost:${port}"

    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=8G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "GPU=Y")
    run_args+=(--device=/dev/kvm)
    run_args+=(--volume "${PWD}/${image_file}:/boot.${image_type}")
    run_args+=(docker.io/qemux/qemu)

    if command -v xdg-open >/dev/null 2>&1; then
        (sleep 30 && xdg-open "http://localhost:${port}") &
    fi

    podman run "${run_args[@]}"

[group('Run Virtual Machine')]
run-vm-qcow2 target_image=("localhost/" + image_name) tag=default_tag: && (_run-vm target_image tag "qcow2")

[group('Run Virtual Machine')]
run-vm-raw target_image=("localhost/" + image_name) tag=default_tag: && (_run-vm target_image tag "raw")

[group('Run Virtual Machine')]
run-vm-iso target_image=("localhost/" + image_name) tag=default_tag: && (_run-vm target_image tag "iso")

# Use systemd-vmspawn when you want a local VM without the qemu container

# wrapper. Set rebuild=1 to rebuild the requested image type first.
[group('Run Virtual Machine')]
spawn-vm rebuild="0" image_type="qcow2" ram="6G":
    #!/usr/bin/env bash
    set -euo pipefail

    image_type="{{ image_type }}"

    if [[ "{{ rebuild }}" -eq 1 ]]; then
        echo "Rebuilding the ${image_type} image"
        just "rebuild-${image_type}"
    fi

    systemd-vmspawn \
        -M "bootc-image" \
        --console=gui \
        --cpus=2 \
        --ram="$(echo {{ ram }} | /usr/bin/numfmt --from=iec)" \
        --network-user-mode \
        --vsock=false \
        --pass-ssh-key=false \
        -i "./output/**/*.${image_type}"

# Shellcheck every shell script shipped by the repo.
lint:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v shellcheck >/dev/null 2>&1; then
        echo "shellcheck could not be found. Please install it." >&2
        exit 1
    fi

    /usr/bin/find . -iname "*.sh" -type f -exec shellcheck "{}" ';'

# Rewrite shell scripts in place with shfmt.
format:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v shfmt >/dev/null 2>&1; then
        echo "shfmt could not be found. Please install it." >&2
        exit 1
    fi

    /usr/bin/find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'
