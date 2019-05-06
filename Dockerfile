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
COPY backup.sh /root/backup.sh
COPY functions.sh /root/functions.sh
RUN chmod +x /root/backup.sh

## CMD
CMD printenv | sed 's/^\(.*\)$/export \1/g' > /root/project_env.sh && cron && touch /var/log/backup-cron/cron.log && tail -f /var/log/backup-cron/cron.log
