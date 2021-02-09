## Update only from lts to lts
FROM ubuntu:18.04

## Defaults
WORKDIR /root/

## Install Python 3, AWSCli, MySQL and Python simple HTTP Server
RUN apt update && apt install -y python3 python3-pip mysql-client-5.7 && pip3 install awscli && pip3 install simple_http_server

## Setup HTTP Server
COPY webserver.py /root/webserver.py

## Configure Crontab
RUN apt-get install cron
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
