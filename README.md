# mysql-s3-backup
[![Build](https://github.com/avides/mysql-s3-backup/workflows/release/badge.svg)](https://github.com/avides/mysql-s3-backup/actions)
[![Nightly build](https://github.com/avides/mysql-s3-backup/workflows/nightly/badge.svg)](https://github.com/avides/mysql-s3-backup/actions)
[![Docker Pulls](https://img.shields.io/docker/pulls/avides/mysql-s3-backup.svg)](https://hub.docker.com/r/avides/mysql-s3-backup)

This script is used to backup a MySQL Server, ZIP the data and upload it to Amazon S3. It will dump, zip and upload each table in a separate "sql.gz"-file. This script will be executed by a specified cron expression.

## Requirements

- Docker
- MySQL > 5.7

## Usage

Set up your variables in the placeholder and run the following command on your docker server:
```
docker run \
-d \
--name=mysql-s3-backup \
--env CRON_EXPR="0 18 * * * (Info: UTC-Timezone)" \
--env S3_BUCKET_NAME="AWS_BUCKET_NAME" \
--env S3_ACCESS_KEY="AWS_ACCESS_KEY" \
--env S3_SECRET_KEY="AWS_SECRET_KEY" \
--env S3_REGION="AWS_REGION" \
--env MYSQL_HOST="MYSQL_HOST" \
--env MYSQL_HOST_ALIAS="MYSQL_HOST_ALIAS (default: ${MYSQL_HOST}" \
--env MYSQL_PORT="MYSQL_PORT (default: 3306)" \
--env MYSQL_BACKUP_USER="root" \
--env MYSQL_BACKUP_PASS="MYSQL_BACKUP_PASS" \
-p 9300:9300 \
avides/mysql-s3-backup:2.5.3
```

### Build & Test

The following commands are useful if you want to run the code locally.

```
docker build -t mysql-s3-backup-dev .

docker run \
-d \
--name=mysql-s3-backup \
--env CRON_EXPR="0 18 * * * (Info: UTC-Timezone)" \
--env S3_BUCKET_NAME="AWS_BUCKET_NAME" \
--env S3_ACCESS_KEY="AWS_ACCESS_KEY" \
--env S3_SECRET_KEY="AWS_SECRET_KEY" \
--env S3_REGION="AWS_REGION" \
--env MYSQL_HOST_ALIAS="MYSQL_HOST_ALIAS (default: ${MYSQL_HOST}" \
--env MYSQL_HOST="MYSQL_HOST" \
--env MYSQL_PORT="MYSQL_PORT (default: 3306)" \
--env MYSQL_BACKUP_USER="root" \
--env MYSQL_BACKUP_PASS="MYSQL_BACKUP_PASS" \
-p 9300:9300 \
mysql-s3-backup-dev

docker logs -f mysql-s3-backup

docker exec -it mysql-s3-backup /bin/bash
```

## Metrics

This container delivers some metrics about the MySQL backups. The metrics are available to the HTTP endpoint "/metrics" on port 9300. Following metrics are collected:

| Name | Datatype |
|---|---|
| mysql_s3_backup_successful | gauge (1=successful / 0=failed) |
| mysql_s3_backup_start_timestamp | gauge (timestamp in milliesconds) |
| mysql_s3_backup_file_size_in_bytes{database="database", table="table"} | gauge (file size in bytes) |
| mysql_s3_backup_duration_in_ms{database="database", table="table"} | gauge (duration in millieseconds) |

## Grafana dashboard

To use the preconfigured dashboard for Grafana you have to import the [Config-File](grafana-dashboard/config.json) to your Grafana instance.

![Grafana dashboard example](grafana-dashboard/example.png?raw=true "Grafana dashboard example")
