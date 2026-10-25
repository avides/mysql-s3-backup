#!/bin/bash

## Setup
## Bash replacement instead of sed, so cron expressions like "*/5 * * * *" work
CRONTAB=$(cat /app/crontab)
echo "${CRONTAB//CRON_EXPR/$CRON_EXPR}" > /app/data/crontab

## Start metrics endpoint
python3 /app/webserver.py &

## Starting (supercronic in foreground, the backup inherits the environment and its output goes unchanged to the container log)
exec supercronic -passthrough-logs /app/data/crontab
