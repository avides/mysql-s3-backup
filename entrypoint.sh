## Setup
printenv | grep -E 'PATH|S3_|MYSQL_' | sed 's/^\(.*\)$/export \1"/g' | sed '/=/s//="/' > /root/project_env.sh
sed -i -e "s#CRON_EXPR#${CRON_EXPR}#g" /etc/cron.d/backup-cron

## Start metrics endpoint
mkdir /var/log/webserver
python3 /root/webserver.py > /var/log/webserver/webserver.log &

## Starting
cron && touch /var/log/backup-cron/cron.log && tail -f /var/log/backup-cron/cron.log
