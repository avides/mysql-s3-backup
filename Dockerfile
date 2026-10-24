## Update only from lts to lts
FROM ubuntu:26.04

## Defaults
WORKDIR /root/

## Install MySQL-Client, Python 3 (metrics endpoint), Cron and tools for the AWS-CLI
RUN apt update && apt install -y mysql-client python3 cron curl unzip

## Install AWS-CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
RUN unzip awscliv2.zip
RUN ./aws/install

## Setup HTTP Server
COPY webserver.py /root/webserver.py

## Configure Crontab
COPY crontab /etc/cron.d/backup-cron
RUN chmod 0644 /etc/cron.d/backup-cron
RUN mkdir /var/log/backup-cron

## Move scripts
COPY entrypoint.sh /root/entrypoint.sh
COPY backup.sh /root/backup.sh
COPY functions.sh /root/functions.sh
COPY metrics.txt /root/metrics.txt
RUN chmod +x /root/backup.sh /root/entrypoint.sh

## CMD
CMD /root/entrypoint.sh
