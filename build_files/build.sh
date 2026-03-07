#!/usr/bin/env bash
set -euo pipefail

# Add the Tailscale repository first so dnf can resolve the package below.
cp /ctx/tailscale.repo /etc/yum.repos.d/tailscale.repo

# Install the tools this image is opinionated about:
# - vim/btop/rpmconf for day-to-day admin work
# - qemu-guest-agent for better VM behavior
# - cockpit-* for browser-based management
# - tailscale for remote connectivity
dnf5 install -y \
  vim \
  btop \
  rpmconf \
  qemu-guest-agent \
  cockpit-podman \
  cockpit-ostree \
  cockpit-selinux \
  cockpit-storaged \
  tailscale

# Keep the image small and opinionated by dropping nano.
dnf5 remove -y nano
dnf5 clean all

# Enable sshd inside the image. The "|| true" keeps the build from failing if
# systemctl reports a harmless warning while running in the container context.
systemctl enable sshd.service || true
