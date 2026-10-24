## Update only from lts to lts
FROM ubuntu:26.04

## Defaults
WORKDIR /root/

## Install MySQL-Client, pigz (parallel gzip), Python 3 (metrics endpoint), Cron and tools for the AWS-CLI
RUN apt update && apt install -y mysql-client pigz python3 cron curl unzip \
    && rm -rf /var/lib/apt/lists/*

## Install AWS-CLI
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip \
    && unzip -q awscliv2.zip \
    && ./aws/install \
    && rm -r aws awscliv2.zip
## Bigger parts for streamed uploads: the size is unknown, max. 10,000 parts -> ~640 GB per file instead of ~78 GB
RUN aws configure set default.s3.multipart_chunksize 64MB

## Setup HTTP Server
COPY webserver.py /root/webserver.py

## Configure Crontab
COPY crontab /etc/cron.d/backup-cron
RUN chmod 0644 /etc/cron.d/backup-cron

## Move scripts
COPY entrypoint.sh /root/entrypoint.sh
COPY backup.sh /root/backup.sh
COPY functions.sh /root/functions.sh
COPY metrics.txt /root/metrics.txt
RUN chmod +x /root/backup.sh /root/entrypoint.sh

## Healthcheck: cron (PID 1) and metrics endpoint
HEALTHCHECK --interval=1m --timeout=10s --start-period=30s \
    CMD python3 -c "import pathlib, urllib.request; assert pathlib.Path('/proc/1/comm').read_text().strip() == 'cron'; urllib.request.urlopen('http://localhost:9300/metrics', timeout=5)"

## CMD
CMD ["/root/entrypoint.sh"]
