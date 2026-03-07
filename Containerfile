# Stage 1: copy repo-managed helper files into a tiny scratch image.
# The final stage can then mount only the files it needs instead of copying the
# entire git checkout into the build context.
FROM scratch AS ctx
COPY build_files /

# Stage 2: start from Fedora's bootc base image.
FROM quay.io/fedora/fedora-bootc

# These build args are intentionally empty/disabled by default so forks of this
# repo do not inherit a baked-in admin account or SSH key. Local builds and
# GitHub Actions can opt in when they need them.
ARG ENABLE_CORE_USER=false
ARG CORE_SSH_PUBLIC_KEY=

# Mount caches during the package install step so repeat builds are faster, but
# keep the resulting image clean.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    ENABLE_CORE_USER="${ENABLE_CORE_USER}" \
    CORE_SSH_PUBLIC_KEY="${CORE_SSH_PUBLIC_KEY}" \
    /ctx/build.sh

# bootc ships a linter for common image-layout mistakes; run it before publish.
RUN bootc container lint
