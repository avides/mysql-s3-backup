## Update only from lts to lts
FROM ubuntu:26.04

## Version of supercronic (checksum of supercronic-linux-amd64)
ARG SUPERCRONIC_VERSION=v0.2.49
ARG SUPERCRONIC_SHA256=a53ae236602c7338aba3fbaff40bda6300eae3b9fedb8261eb06cfe3724430c1

## Defaults
## Settings of the AWS-CLI for every user (the container does not run as root)
ENV AWS_CONFIG_FILE=/etc/aws/config
WORKDIR /app/

## Install MySQL-Client, pigz (parallel gzip), Python 3 (metrics endpoint), supercronic (cron for containers, runs without root) and tools for the AWS-CLI,
## then the AWS-CLI with bigger parts for streamed uploads: the size is unknown, max. 10,000 parts -> ~312 GB per file
## instead of ~78 GB (32 MB needs ~140 MB memory for the upload, 64 MB already ~350 MB)
RUN apt update && apt install -y --no-install-recommends ca-certificates curl mysql-client pigz python3 unzip \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL --proto '=https' --tlsv1.2 "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip \
    && unzip -q awscliv2.zip \
    && ./aws/install \
    && rm -r aws awscliv2.zip \
    && aws configure set default.s3.multipart_chunksize 32MB \
    && chmod 0644 "$AWS_CONFIG_FILE" \
    && curl -fsSL --proto '=https' --tlsv1.2 "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64" -o /usr/local/bin/supercronic \
    && echo "${SUPERCRONIC_SHA256}  /usr/local/bin/supercronic" | sha256sum -c - \
    && chmod +x /usr/local/bin/supercronic \
    && useradd --system --uid 10001 --user-group --home-dir /app/data --no-create-home --shell /usr/sbin/nologin s3-backup \
    && mkdir -p /app/data \
    && chown s3-backup:s3-backup /app/data

## Scripts and crontab template belong to root (the backup user cannot change them),
## the backup user only writes into /app/data (metrics, crontab, lock, pipes of the running backup)
COPY --chmod=0755 entrypoint.sh backup.sh functions.sh webserver.py /app/
COPY --chmod=0644 crontab /app/
COPY --chown=s3-backup:s3-backup metrics.txt /app/data/

## Run without root
USER s3-backup
WORKDIR /app/data/

## Healthcheck: supercronic (PID 1) and metrics endpoint
HEALTHCHECK --interval=1m --timeout=10s --start-period=30s \
    CMD python3 -c "import pathlib, urllib.request; assert pathlib.Path('/proc/1/comm').read_text().strip() == 'supercronic'; urllib.request.urlopen('http://localhost:9300/metrics', timeout=5)"

## CMD
CMD ["/app/entrypoint.sh"]
