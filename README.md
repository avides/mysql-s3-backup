# mysql-s3-backup

## Docker
[Dockerhub](https://hub.docker.com/r/avides/mysql-s3-backup/)

### Run as Docker Service
```
docker service create \
--name=mysql-s3-backup \
--constraint 'node.labels.environment==production' \
--env CRON_EXPR="0 18 * * * (Info: UTC-Timezone)" \
--env S3_BUCKET_NAME="AWS_BUCKET_NAME" \
--env S3_ACCESS_KEY="AWS_ACCESS_KEY" \
--env S3_SECRET_KEY="AWS_SECRET_KEY" \
--env S3_REGION="AWS_REGION" \
--env MYSQL_HOST="MYSQL_HOST" \
--env MYSQL_PORT="MYSQL_PORT (default: 3306)" \
--env MYSQL_BACKUP_USER="MYSQL_BACKUP_USER" \
--env MYSQL_BACKUP_PASS="MYSQL_BACKUP_PASS" \
--publish mode=host,target=9300 \
--reserve-cpu=0.05 \
--reserve-memory=50M \
--limit-cpu=1 \
--limit-memory=200M \
--with-registry-auth \
avides/mysql-s3-backup:2.3.0
```

### Build & Test
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
--env MYSQL_PORT="MYSQL_PORT (default: 3306)" \
--env MYSQL_BACKUP_USER="root" \
--env MYSQL_BACKUP_PASS="MYSQL_BACKUP_PASS" \
-p 9300:9300 \
mysql-s3-backup-dev

docker logs -f mysql-s3-backup

docker exec -i -t mysql-s3-backup /bin/bash
```
