#!/bin/bash

function backup_mysql_and_upload
{
	DB_HOST=$1
	DB_PORT=$2
	DB_USER=$3
	DB_PASSWORD=$4
	STORAGE_PATH=$5
	
	backup_mysql $DB_HOST $DB_PORT $DB_USER $DB_PASSWORD $STORAGE_PATH
	
	## remove temp files
	rm -rf $BACKUP_PATH
}

function backup_mysql
{
	DB_HOST=$1
	DB_PORT=$2
	DB_USER=$3
	DB_PASSWORD=$4
	STORAGE_PATH=$5

	echo "Host $DB_HOST started ($(date))"

	export START_DATE=$(date +"%Y-%m-%d")

	for databaseName in $(mysql -NBA --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD -e 'show databases' -s --skip-column-names|egrep -vi "information_schema|performance_schema|sys|innodb|mysql|tmp");
	do
		echo "	Database $databaseName@$DB_HOST started"

		mkdir -p dump_logs/$databaseName

		for tableName in $(mysql -NBA --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD --database=$databaseName -e 'show tables')
		do
			mkdir -p $STORAGE_PATH/$databaseName

			mkfifo pipe
			tail -n1 pipe > dump_logs/$databaseName/$tableName.log &
			mysqldump --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD $databaseName $tableName | tee pipe | gzip > $STORAGE_PATH/$databaseName/$tableName.sql.gz
			rm pipe

			if ! grep "Dump completed on" dump_logs/$databaseName/$tableName.log; then
				sed -i -e 's/1/0/g' /root/metrics.txt
				exit 0;
			fi

			# Sync to S3 and remove temp files
			aws s3 cp --recursive "$STORAGE_PATH/$databaseName/" s3://$BUCKET_NAME/$START_DATE/$DB_HOST/$databaseName/
            rm -rf $STORAGE_PATH/$databaseName
		done

		rm -r dump_logs

		echo "	Database $databaseName@$DB_HOST finished"
	done

	echo "Host $DB_HOST finished ($(date))"
}
