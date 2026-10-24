# mysql-s3-backup
[![Build](https://github.com/avides/mysql-s3-backup/workflows/release/badge.svg)](https://github.com/avides/mysql-s3-backup/actions)
[![Nightly build](https://github.com/avides/mysql-s3-backup/workflows/nightly/badge.svg)](https://github.com/avides/mysql-s3-backup/actions)
[![Docker Pulls](https://img.shields.io/docker/pulls/avides/mysql-s3-backup.svg)](https://hub.docker.com/r/avides/mysql-s3-backup)

This docker image is used to backup a MySQL server into Amazon S3. It will dump, zip and stream each table directly into a separate "sql.gz"-file in S3 (no local temporary files). The backup is executed by a specified cron expression.

## Requirements

- Docker
- MySQL >= 8.0

## Run as Docker Service
```
docker service create \
--name mysql-s3-backup \
--env CRON_EXPR="0 18 * * * (Info: UTC-Timezone)" \
--env S3_BUCKET_NAME="AWS_BUCKET_NAME" \
--env S3_ACCESS_KEY="AWS_ACCESS_KEY" \
--env S3_SECRET_KEY="AWS_SECRET_KEY" \
--env S3_REGION="AWS_REGION" \
--env MYSQL_HOST="MYSQL_HOST" \
--env MYSQL_HOST_ALIAS="MYSQL_HOST_ALIAS (default: ${MYSQL_HOST})" \
--env MYSQL_PORT="MYSQL_PORT (default: 3306)" \
--env MYSQL_BACKUP_USER="MYSQL_BACKUP_USER" \
--env MYSQL_BACKUP_PASS="MYSQL_BACKUP_PASS" \
--publish 9300:9300 \
--reserve-cpu=0.05 \
--reserve-memory=50M \
--limit-cpu=1 \
--limit-memory=200M \
--with-registry-auth \
avides/mysql-s3-backup:latest
```

## Build & Test
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
--env MYSQL_HOST="MYSQL_HOST" \
--env MYSQL_HOST_ALIAS="MYSQL_HOST_ALIAS (default: ${MYSQL_HOST})" \
--env MYSQL_PORT="MYSQL_PORT (default: 3306)" \
--env MYSQL_BACKUP_USER="MYSQL_BACKUP_USER" \
--env MYSQL_BACKUP_PASS="MYSQL_BACKUP_PASS" \
-p 9300:9300 \
mysql-s3-backup-dev

docker logs -f mysql-s3-backup

docker exec -it mysql-s3-backup /bin/bash
```

### Trigger backup manually
Caution: Please avoid concurrent backup processes (e.g. via cron & manual backup)!

The following command must be executed inside the container.
Therefore, you must log in inside the container or pass the command to the container.

```shell
/root/backup.sh >> /var/log/backup-cron/cron.log
```

## Metrics

This container delivers some metrics about the MySQL backups. The metrics are available to the HTTP endpoint "/metrics" on port 9300. Following metrics are collected:

| Name | Datatype |
|---|---|
| mysql_s3_backup_successful | gauge (1=successful / 0=failed) |
| mysql_s3_backup_start_timestamp | gauge (timestamp in milliseconds) |
| mysql_s3_backup_file_size_in_bytes{database="database", table="table"} | gauge (file size in bytes) |
| mysql_s3_backup_duration_in_ms{database="database", table="table"} | gauge (duration in milliseconds) |

## Grafana dashboard

To use the preconfigured dashboard for Grafana you have to import the [Config-File](grafana-dashboard/config.json) to your Grafana instance.

![Grafana dashboard example](grafana-dashboard/example.png?raw=true "Grafana dashboard example")
