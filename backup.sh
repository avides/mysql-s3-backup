#!/bin/bash

## Includes
source functions.sh

## Check if variables are given
if [ -z ${S3_ACCESS_KEY+x} ]; then
    echo "WARNING: Please set the S3_ACCESS_KEY or create /root/.aws/credentials file!"
else
    ## Set S3 environment variables
    export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY
fi

if [ -z ${S3_SECRET_KEY+x} ]; then
    echo "WARNING: Please set the S3_SECRET_KEY or create /root/.aws/credentials file!"
else
    ## Set S3 environment variables
    export AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY
fi

if [ -z ${S3_REGION+x} ]; then
    echo "ERROR: Please set the S3_REGION!"
    exit 1
fi

if [ -z ${S3_BUCKET_NAME+x} ]; then
    echo "ERROR: Please set the S3_BUCKET_NAME!"
    exit 1
fi

if [ -z ${S3_PATH_FORMAT+x} ]; then
    echo "Use default S3_PATH_FORMAT..."
    export S3_PATH_FORMAT=@MYSQL_HOST_ALIAS/@databaseName/%Y-%m-%d
fi

if [ -z ${S3_TABLE_FORMAT+x} ]; then
    echo "Use default S3_TABLE_FORMAT..."
    echo "$S3_TABLE_FORMAT"
    export S3_TABLE_FORMAT=%Y-%m-%d-%H-%M-@tableName
fi

if [ -z ${MYSQL_HOST_ALIAS+x} ]; then
    echo "Use default MySQL host alias: $MYSQL_HOST"
    MYSQL_HOST_ALIAS=$MYSQL_HOST
fi

if [ -z ${MYSQL_HOST+x} ]; then
    echo "ERROR: Please set the MYSQL_HOST!"
    exit 1
fi

if [ -z ${MYSQL_PORT+x} ]; then
    echo "Use default MySQL port 3306..."
    MYSQL_PORT=3306
fi

if [ -z ${MYSQL_BACKUP_USER+x} ]; then
    echo "ERROR: Please set the MYSQL_BACKUP_USER!"
    exit 1
fi

if [ -z ${MYSQL_BACKUP_PASS+x} ]; then
    echo "ERROR: Please set the MYSQL_BACKUP_PASS!"
    exit 1
fi

## Settings
BACKUP_PATH="/root/backups"
BUCKET_NAME=${S3_BUCKET_NAME}

## Set S3 environment variables
export AWS_DEFAULT_REGION=$S3_REGION

## MySQL-Servers
echo "STARTING BACKUP ($(date))"
add_metric "mysql_s3_backup_start_timestamp" $(($(date +%s%N)/1000000))
backup_mysql_and_upload ${MYSQL_HOST} ${MYSQL_PORT} ${MYSQL_BACKUP_USER} ${MYSQL_BACKUP_PASS} $BACKUP_PATH
echo "FINISHED BACKUP ($(date))"
