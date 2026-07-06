ARG KOPIA_IMAGE_TAG=0.23.1
ARG RCLONE_IMAGE_TAG=1.69

FROM rclone/rclone:${RCLONE_IMAGE_TAG} AS rclone
FROM kopia/kopia:${KOPIA_IMAGE_TAG}

COPY --from=rclone /usr/local/bin/rclone /usr/bin/rclone
