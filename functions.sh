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
	START_TIME_IN_S=$SECONDS

	for databaseName in $(mysql -NBA --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD -e 'show databases' -s --skip-column-names|egrep -vi "information_schema|performance_schema|sys|innodb|mysql|tmp");
	do
		echo "	Database $databaseName@$DB_HOST started"

		mkdir -p dump_logs/$databaseName

		for tableName in $(mysql -NBA --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD --database=$databaseName -e 'show tables')
		do
			mkdir -p $STORAGE_PATH/$databaseName

			# Create and validate MySQL dump
			mkfifo pipe
			tail -n1 pipe > dump_logs/$databaseName/$tableName.log &
			mysqldump --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD $databaseName $tableName | tee pipe | gzip > $STORAGE_PATH/$databaseName/$tableName.sql.gz
			rm pipe

			if ! grep "Dump completed on" dump_logs/$databaseName/$tableName.log; then
				add_metric "mysql_s3_backup_successful" "0"
				exit 0;
			fi

			# Sync to S3 and remove temp files
			# aws s3 cp --recursive "$STORAGE_PATH/$databaseName/" s3://$BUCKET_NAME/$START_DATE/$DB_HOST/$databaseName/

			# Create file size metrics
			add_metric "mysql_s3_backup_file_size_in_bytes{database=\"${databaseName}\",table=\"${tableName}\"}" $(wc -c < $STORAGE_PATH/$databaseName/$tableName.sql.gz)
			add_metric "mysql_s3_backup_duration_in_seconds" $(($SECONDS - $START_TIME_IN_S))

			# Cleanup
            rm -rf $STORAGE_PATH/$databaseName
		done

		rm -r dump_logs

		echo "	Database $databaseName@$DB_HOST finished"
	done

	# Create duration metrics
	add_metric "mysql_s3_backup_duration_in_seconds" $(($SECONDS - $START_TIME_IN_S))

	echo "Host $DB_HOST finished ($(date))"
}

function add_metric
{
	METRIC_NAME=$1
	METRIC_VALUE=$2
	METRIC_NAME_FOR_DOCS=$(echo "$METRIC_NAME" | cut -f1 -d"{")

	if ! grep $METRIC_NAME /root/metrics.txt; then
		if ! grep $METRIC_NAME_FOR_DOCS /root/metrics.txt; then
			echo "# HELP $METRIC_NAME_FOR_DOCS" >> /root/metrics.txt
			echo "# TYPE $METRIC_NAME_FOR_DOCS gauge" >> /root/metrics.txt
			echo "$METRIC_NAME $METRIC_VALUE" >> /root/metrics.txt
		else
			# Add after last match in metrics.txt to prevent right order
			# sed "1h;1!H;$!d;x;s/.*$METRIC_NAME.*/&$METRIC_NAME $METRIC_VALUE/" /root/metrics.txt
		fi
	else
		sed -i -e "s/$METRIC_NAME.[0-9].*/$METRIC_NAME $METRIC_VALUE/g" /root/metrics.txt
	fi
}
