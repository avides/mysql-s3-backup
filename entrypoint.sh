#!/bin/bash

## Setup
## Environment for cron, properly quoted (special characters in values are kept)
export -p | grep -E '^declare -x (PATH|AWS_[A-Z_]+|S3_[A-Z_]+|MYSQL_[A-Z_]+)=' > /root/project_env.sh
## Bash replacement instead of sed, so cron expressions like "*/5 * * * *" work
CRONTAB=$(cat /etc/cron.d/backup-cron)
echo "${CRONTAB//CRON_EXPR/$CRON_EXPR}" > /etc/cron.d/backup-cron

## Start metrics endpoint
python3 /root/webserver.py &

## Starting (cron in foreground, backup output goes to the container log)
exec cron -f
