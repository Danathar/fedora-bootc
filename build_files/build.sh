#!/usr/bin/env bash
set -euo pipefail

# 1) Add tailscale repo
cp /ctx/tailscale.repo /etc/yum.repos.d/tailscale.repo

# 2) Packages (your existing BlueBuild logic)
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

# 3) Create login user and add to wheel
USER_NAME="core"        # change to whatever you want
useradd -m -s /bin/bash -G wheel "${USER_NAME}" || true
passwd -l "${USER_NAME}" || true    # lock password, SSH keys only

# Optional: ensure wheel has sudo
sed -i 's/^# %wheel/%wheel/' /etc/sudoers || true

# 4) (Optional) Install SSH key for that user
# Put your key in build_files/core-authorized_keys
if [ -f /ctx/core-authorized_keys ]; then
  mkdir -p "/home/${USER_NAME}/.ssh"
  cp /ctx/core-authorized_keys "/home/${USER_NAME}/.ssh/authorized_keys"
  chown -R "${USER_NAME}:${USER_NAME}" "/home/${USER_NAME}/.ssh"
  chmod 700 "/home/${USER_NAME}/.ssh"
  chmod 600 "/home/${USER_NAME}/.ssh/authorized_keys"
fi

# 5) Make sure SSHD is running
systemctl enable sshd.service || true

