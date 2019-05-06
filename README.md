# mysql-s3-backup

## Docker
[Dockerhub](https://hub.docker.com/r/avides/mysql-s3-backup/)

### Produktiv
```
docker service create \
--name=mysql-s3-backup \
--constraint 'node.labels.environment==production' \
--env S3_BUCKET_NAME="AWS_BUCKET_NAME" \
--env S3_ACCESS_KEY="AWS_ACCESS_KEY" \
--env S3_SECRET_KEY="AWS_SECRET_KEY" \
--env S3_REGION="AWS_REGION" \
--env MYSQL_HOST="MYSQL_HOST" \
--env MYSQL_PORT="MYSQL_PORT (default: 3306)" \
--env MYSQL_BACKUP_USER="MYSQL_BACKUP_USER" \
--env MYSQL_BACKUP_PASS="MYSQL_BACKUP_PASS" \
--reserve-cpu=0.5 \
--reserve-memory=100M \
--limit-cpu=1 \
--limit-memory=200M \
--with-registry-auth \
avides/mysql-s3-backup:2.0.1
```

### Build & Test
```
docker build -t mysql-s3-backup-dev .

docker run \
-d \
--name=mysql-s3-backup \
--env S3_BUCKET_NAME="AWS_BUCKET_NAME" \
--env S3_ACCESS_KEY="AWS_ACCESS_KEY" \
--env S3_SECRET_KEY="AWS_SECRET_KEY" \
--env S3_REGION="AWS_REGION" \
--env MYSQL_HOST="MYSQL_HOST" \
--env MYSQL_PORT="MYSQL_PORT (default: 3306)" \
--env MYSQL_BACKUP_USER="root" \
--env MYSQL_BACKUP_PASS="MYSQL_BACKUP_PASS" \
mysql-s3-backup-dev

docker logs -f mysql-s3-backup

docker exec -i -t mysql-s3-backup /bin/bash
```
