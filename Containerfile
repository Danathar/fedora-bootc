# Stage 1: copy repo-managed helper files into a tiny scratch image.
# The final stage can then mount only the files it needs instead of copying the
# entire git checkout into the build context.
FROM scratch AS ctx
COPY build_files /

# Stage 2: start from Fedora's bootc base image.
FROM quay.io/fedora/fedora-bootc

# Mount caches during the package install step so repeat builds are faster, but
# keep the resulting image clean.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# Use sysusers/tmpfiles so the admin account is created declaratively on boot.
COPY --from=ctx /core-user.conf /usr/lib/sysusers.d/core-user.conf
COPY --from=ctx /core-ssh.conf /usr/lib/tmpfiles.d/core-ssh.conf

# bootc ships a linter for common image-layout mistakes; run it before publish.
RUN bootc container lint
