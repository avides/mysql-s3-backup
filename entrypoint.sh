## Setup
printenv | grep -E 'PATH|S3_BUCKET_NAME|S3_ACCESS_KEY|S3_SECRET_KEY|S3_REGION|MYSQL_HOST|MYSQL_PORT|MYSQL_BACKUP_USER|MYSQL_BACKUP_PASS' | sed 's/^\(.*\)$/export \1"/g' | sed '/=/s//="/' > /root/project_env.sh
sed -i -e "s/CRON_EXPR/${CRON_EXPR}/g" /etc/cron.d/backup-cron

## Start metrics endpoint
mkdir /var/log/webserver
python3 /root/webserver.py > /var/log/webserver/webserver.log &

## Starting
cron && touch /var/log/backup-cron/cron.log && tail -f /var/log/backup-cron/cron.log
