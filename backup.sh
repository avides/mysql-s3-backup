#!/bin/bash

## Includes
source functions.sh

## Check if variables are given
if [ "${S3_ACCESS_KEY}" == "**None**" ]; then
    echo "ERROR: Please set the S3_ACCESS_KEY!"
    exit 1
fi

if [ "${S3_SECRET_KEY}" == "**None**" ]; then
    echo "ERROR: Please set the S3_SECRET_KEY!"
    exit 1
fi

if [ "${S3_REGION}" == "**None**" ]; then
    echo "ERROR: Please set the S3_REGION!"
    exit 1
fi

if [ "${S3_BUCKET_NAME}" == "**None**" ]; then
    echo "ERROR: Please set the S3_BUCKET_NAME!"
    exit 1
fi

if [ "${MYSQL_HOST+x}" == "**None**" ]; then
    echo "ERROR: Please set the MYSQL_HOST!"
    exit 1
fi

if [ "${MYSQL_PORT+x}" == "**None**" ]; then
    echo "Use default MySQL port 3306..."
    MYSQL_PORT=3306
fi

if [ "${MYSQL_BACKUP_USER+x}" == "**None**" ]; then
    echo "ERROR: Please set the MYSQL_BACKUP_USER!"
    exit 1
fi

if [ "${MYSQL_BACKUP_PASS+x}" == "**None**" ]; then
    echo "ERROR: Please set the MYSQL_BACKUP_PASS!"
    exit 1
fi

## Settings
BACKUP_PATH="/root/backups"
BUCKET_NAME=${S3_BUCKET_NAME}

## Set S3 environment variables
export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY
export AWS_DEFAULT_REGION=$S3_REGION

## MySQL-Servers
echo "STARTING BACKUP ($(date))"
backup_mysql_and_upload ${MYSQL_HOST} ${MYSQL_PORT} ${MYSQL_BACKUP_USER} ${MYSQL_BACKUP_PASS} $BACKUP_PATH
echo "FINISHED BACKUP ($(date))"
