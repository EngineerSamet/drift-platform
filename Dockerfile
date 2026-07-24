# SPDX-License-Identifier: Apache-2.0
#
# The scan image: sbomdrift from PyPI, syft to produce the SBOMs, curl to hand
# the metrics to the Pushgateway.
#
# sbomdrift is installed from the public index rather than copied from a local
# checkout on purpose. If the published artefact is broken, this image fails to
# build, and that is a failure worth having early.

FROM python:3.13-slim@sha256:6771159cd4fa5d9bba1258caf0b82e6b73458c694d178ad97c5e925c2d0e1a91

# Syft is copied from its own published image rather than curl-piped from a
# release page, and pinned to a digest for the same reason every third-party
# step in sealed-build is pinned: a tag is a mutable pointer, a digest is not.
COPY --from=anchore/syft:v1.49.0@sha256:13b53ebabe3d215268c90cf8fb9b875f0183908245f376fd4b3a2cb69d21d484 /syft /usr/local/bin/syft

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    pip install --no-cache-dir sbomdrift==0.1.3

# The job writes its database here; the chart mounts a volume over it so the
# history survives the pod that produced it.
ENV SBOMDRIFT_DB=/data/history.db

# Runs unprivileged. Nothing here needs root, and a scan job holding root is a
# large blast radius for a small task.
RUN useradd --create-home --uid 10001 scanner \
 && mkdir -p /data && chown scanner:scanner /data

USER 10001
WORKDIR /data

ENTRYPOINT ["/bin/bash"]
