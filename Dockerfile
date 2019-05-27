## Update only from lts to lts
FROM ubuntu:18.04

## Defaults
WORKDIR /root/

## Install AWSCli & MySQL
RUN apt-get update && apt-get install -y python python-pip mysql-client-5.7 && pip install awscli

## Configure Crontab
RUN apt-get install cron
COPY crontab /etc/cron.d/backup-cron
RUN chmod 0644 /etc/cron.d/backup-cron
RUN mkdir /var/log/backup-cron

## Move scripts
COPY entrypoint.sh /root/entrypoint.sh
COPY backup.sh /root/backup.sh
COPY functions.sh /root/functions.sh
RUN chmod +x /root/backup.sh /root/entrypoint.sh

## CMD
CMD /root/entrypoint.sh
