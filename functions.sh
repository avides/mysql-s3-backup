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

	for databaseName in $(mysql -NBA --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD -e 'show databases' -s --skip-column-names|egrep -vi "information_schema|performance_schema|sys|innodb|mysql|tmp");
	do
		echo "	Database $databaseName@$DB_HOST started"

		for tableName in $(mysql -NBA --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD --database=$databaseName -e 'show tables')
		do
			mkdir -p $STORAGE_PATH/$databaseName
			mysqldump --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD $databaseName $tableName > $STORAGE_PATH/$databaseName/$tableName.sql

			# Sync to S3 and remove temp files
			aws s3 cp --recursive "$STORAGE_PATH/$databaseName/" s3://$BUCKET_NAME/$(date +"%Y-%m-%d")/$DB_HOST/$databaseName/
            rm -rf $STORAGE_PATH/$databaseName
		done

		echo "	Database $databaseName@$DB_HOST finished"
	done

	echo "Host $DB_HOST finished ($(date))"
}
