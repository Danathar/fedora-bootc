# Stage to hold build scripts and config
FROM scratch AS ctx
COPY build_files /   

# Base Image
FROM quay.io/fedora/fedora-bootc

# Optional: make /opt immutable if needed
# RUN rm /opt && mkdir /opt

# Run your package/config script
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# Install sysusers and tmpfiles definitions for the 'core' user + SSH key
COPY --from=ctx /core-user.conf /usr/lib/sysusers.d/core-user.conf
COPY --from=ctx /core-ssh.conf  /usr/lib/tmpfiles.d/core-ssh.conf

# Lint final image
RUN bootc container lint

