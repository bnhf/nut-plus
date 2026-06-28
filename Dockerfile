#BUILD_DATE=$(date +%Y.%m.%d) && docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -f Dockerfile -t bnhf/nut-plus:latest -t bnhf/nut-plus:$BUILD_DATE --build-arg BUILD_DATE=$BUILD_DATE . --push --no-cache
FROM alpine:3.22
LABEL maintainer="Scott Ueland (https://github.com/bnhf)"

ARG BUILD_DATE
LABEL version="${BUILD_DATE}"

ENV NUT_QUIET_INIT_UPSNOTIFY=true \
    TLS_FILE=/etc/ssl/cert.pem \
    MSMTP_LOG=-
ENV NUT_PLUS_VERSION=${BUILD_DATE:-unknown}

# Install required packages
RUN apk add --no-cache \
  bash \
  nut nut-dev \
  linux-pam \
  libusb libusb-dev \
  net-snmp-libs net-snmp-dev \
  neon neon-dev \
  gawk sed \
  tzdata dbus \
  syslog-ng busybox-openrc \
  msmtp ca-certificates curl jq \
  && rc-update add syslog boot \
  && mkdir -p /opt/nut /var/run/nut/upssched \
  && chmod 700 /var/run/nut

# Copy NUT config files to /opt/nut to be copied by start.sh
COPY ./config/ /opt/nut/
COPY start.sh .
RUN chmod +x start.sh

# Expose default NUT port
EXPOSE 3493

# Set the container entrypoint
CMD ["./start.sh"]
