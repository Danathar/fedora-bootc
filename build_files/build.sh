#!/usr/bin/env bash
set -euo pipefail

enable_core_user="${ENABLE_CORE_USER:-false}"
core_ssh_public_key="${CORE_SSH_PUBLIC_KEY:-}"

enable_core_user="$(printf '%s' "${enable_core_user}" | tr '[:upper:]' '[:lower:]')"
core_ssh_public_key="${core_ssh_public_key//$'\r'/}"
core_ssh_public_key="${core_ssh_public_key//$'\n'/}"

# Supplying a public key implies that the image should also create the matching
# local admin account. This keeps the opt-in path short for people templating
# the repo while still leaving the default image free of personal credentials.
if [[ -n "${core_ssh_public_key}" ]]; then
  enable_core_user="true"
fi

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

# Generate the optional admin-user files declaratively inside the image instead
# of tracking a real key in git. systemd-sysusers creates the account at boot,
# and systemd-tmpfiles seeds authorized_keys if a public key was supplied.
# Forks start with no extra user by default.
rm -f /usr/lib/sysusers.d/core-user.conf /usr/lib/tmpfiles.d/core-ssh.conf

if [[ "${enable_core_user}" == "true" ]]; then
  install -D -m 0644 /ctx/core-user.conf.example /usr/lib/sysusers.d/core-user.conf
fi

if [[ -n "${core_ssh_public_key}" ]]; then
  install -d -m 0755 /usr/lib/tmpfiles.d
  cat > /usr/lib/tmpfiles.d/core-ssh.conf <<EOF
# Generated at build time when CORE_SSH_PUBLIC_KEY is supplied.
d /home/core/.ssh 700 core core -
f~ /home/core/.ssh/authorized_keys 600 core core - [${core_ssh_public_key}]
EOF
fi
