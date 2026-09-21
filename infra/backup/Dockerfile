ARG KOPIA_IMAGE=kopia/kopia:0.23.1@sha256:89fd95ee2942880ca00eae964266958a394421ddbdf69bca62e38afc55f5900e
ARG RCLONE_IMAGE=rclone/rclone:1.69@sha256:1f497a86a6466395e62a5886613a14b7b18809543566ef9fa35fa1371a7ecc0f

FROM ${RCLONE_IMAGE} AS rclone
FROM ${KOPIA_IMAGE}

COPY --from=rclone /usr/local/bin/rclone /usr/bin/rclone
COPY scripts/kopia-entrypoint.sh /usr/local/bin/kopia-entrypoint
COPY scripts/kopia-healthcheck.sh /usr/local/bin/kopia-healthcheck
RUN chmod 0755 /usr/local/bin/kopia-entrypoint /usr/local/bin/kopia-healthcheck

ENTRYPOINT ["/usr/local/bin/kopia-entrypoint"]
