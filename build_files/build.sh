#!/usr/bin/env bash
set -euo pipefail

# 1) Add tailscale repo
cp /ctx/tailscale.repo /etc/yum.repos.d/tailscale.repo

# 2) Packages
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

dnf5 remove -y nano
dnf5 clean all

# 3) Ensure SSHD is enabled
systemctl enable sshd.service || true

