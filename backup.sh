#!/bin/bash

## Includes
source /app/functions.sh

## Only one backup at a time (e.g. cron & manual backup)
exec 9>/app/data/backup.lock
if ! flock -n 9; then
    echo "ERROR: Another backup is still running!" >&2
    exit 1
fi

## Fresh run: no work files of an aborted run, result stays as published until the end
rm -f /app/data/*.metric
BACKUP_SUCCESSFUL=1

## Check if variables are given
if [[ -z ${S3_ACCESS_KEY+x} ]]; then
    abort_backup "Please set the S3_ACCESS_KEY!"
fi

if [[ -z ${S3_SECRET_KEY+x} ]]; then
    abort_backup "Please set the S3_SECRET_KEY!"
fi

if [[ -z ${S3_REGION+x} ]]; then
    abort_backup "Please set the S3_REGION!"
fi

if [[ -z ${S3_BUCKET_NAME+x} ]]; then
    abort_backup "Please set the S3_BUCKET_NAME!"
fi

if [[ -z ${MYSQL_HOST_ALIAS+x} ]]; then
    echo "Use default MySQL host alias: $MYSQL_HOST"
    MYSQL_HOST_ALIAS=$MYSQL_HOST
fi

if [[ -z ${MYSQL_HOST+x} ]]; then
    abort_backup "Please set the MYSQL_HOST!"
fi

if [[ -z ${MYSQL_PORT+x} ]]; then
    echo "Use default MySQL port 3306..."
    MYSQL_PORT=3306
fi

if [[ -z ${MYSQL_BACKUP_USER+x} ]]; then
    abort_backup "Please set the MYSQL_BACKUP_USER!"
fi

if [[ -z ${MYSQL_BACKUP_PASS+x} ]]; then
    abort_backup "Please set the MYSQL_BACKUP_PASS!"
fi

## Settings
BUCKET_NAME=${S3_BUCKET_NAME}

## Set S3 environment variables
export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY
export AWS_DEFAULT_REGION=$S3_REGION

## Backup
echo "STARTING BACKUP ($(date))"
BACKUP_START_TIME_IN_MS=$(($(date +%s%N)/1000000))
publish_start
backup_mysql_and_upload ${MYSQL_HOST} ${MYSQL_PORT} ${MYSQL_BACKUP_USER} ${MYSQL_BACKUP_PASS}
echo "FINISHED BACKUP ($(date))"
