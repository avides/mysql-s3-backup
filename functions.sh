#!/bin/bash

function backup_mysql_and_upload
{
	DB_HOST=$1
	DB_PORT=$2
	DB_USER=$3
	DB_PASSWORD=$4
	STORAGE_PATH=$5

	backup_mysql $DB_HOST $DB_PORT $DB_USER $DB_PASSWORD $STORAGE_PATH

	## create metrics
	merge_metrics_data

	## remove temp files
	rm -rf $STORAGE_PATH
}

function backup_mysql
{
	DB_HOST=$1
	DB_PORT=$2
	DB_USER=$3
	DB_PASSWORD=$4
	STORAGE_PATH=$5

	echo "Host $DB_HOST started ($(date))"

	export S3_PATH_AFTER_DATE_REPLACEMENT=$(date +"$S3_PATH_FORMAT")
	export S3_TABLE_FILENAME_AFTER_DATE_REPLACEMENT=$(date +"$S3_TABLE_FORMAT")

	for databaseName in $(mysql -NBA --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD -e 'show databases' -s --skip-column-names|egrep -vi "information_schema|performance_schema|sys|innodb|mysql|tmp");
	do
		echo "	Database $databaseName@$DB_HOST started"

		mkdir -p dump_logs/$databaseName

		for tableName in $(mysql -NBA --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD --database=$databaseName -e 'show tables')
		do
			START_TIME_IN_MS=$(($(date +%s%N)/1000000))

			mkdir -p $STORAGE_PATH/$databaseName

			## Create MySQL dump
			mkfifo pipe
			tail -n1 pipe > dump_logs/$databaseName/$tableName.log &
			PIDOF_SUCCESS_CHECK=$!

			# Replace @tableName to $tableName (for example)
			S3_TABLE_FILENAME=$(echo "$S3_TABLE_FILENAME_AFTER_DATE_REPLACEMENT" | tr "@" "$")
			# Do variable replacement ($tableName for example)
			S3_TABLE_FILENAME=$(eval echo $S3_TABLE_FILENAME)

			mysqldump --max_allowed_packet=512M --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD $databaseName $tableName | tee pipe | gzip > $STORAGE_PATH/$databaseName/$S3_TABLE_FILENAME.sql.gz
			rm pipe
			wait $PIDOF_SUCCESS_CHECK

			## Validate if MySQL is completed and update metrics
			if ! grep "Dump completed on" dump_logs/$databaseName/$tableName.log; then
				sed -i -e "s/mysql_s3_backup_successful.[0-9].*/mysql_s3_backup_successful 0/g" /root/metrics.txt
				return;
			fi

			# Replace @tableName to $tableName (for example)
			S3_PATH=$(echo "$S3_PATH_AFTER_DATE_REPLACEMENT" | tr "@" "$")
			# Do variable replacement ($tableName for example)
			S3_PATH=$(eval echo $S3_PATH)

			## Sync to S3 and remove temp files
			aws s3 cp --recursive "$STORAGE_PATH/$databaseName/" s3://$BUCKET_NAME/$S3_PATH/

			## Create file size metrics
			add_metric "mysql_s3_backup_file_size_in_bytes{database=\"${databaseName}\",table=\"${tableName}\"}" $(wc -c < $STORAGE_PATH/$databaseName/$tableName.sql.gz)
			add_metric "mysql_s3_backup_duration_in_ms{database=\"${databaseName}\",table=\"${tableName}\"}" $(($(($(date +%s%N)/1000000)) - $START_TIME_IN_MS))

			## Cleanup
            rm -rf $STORAGE_PATH/$databaseName
		done

		rm -r dump_logs

		echo "	Database $databaseName@$DB_HOST finished"
	done

	echo "Host $DB_HOST finished ($(date))"
}

function add_metric
{
	METRIC_NAME=$1
	METRIC_VALUE=$2
	METRIC_NAME_FOR_DOCS=$(echo "$METRIC_NAME" | cut -f1 -d"{")

	if [ ! -f /root/$METRIC_NAME_FOR_DOCS.metric ] ; then
		touch /root/$METRIC_NAME_FOR_DOCS.metric
	fi

	if ! grep $METRIC_NAME /root/$METRIC_NAME_FOR_DOCS.metric ; then
		if ! grep $METRIC_NAME_FOR_DOCS /root/$METRIC_NAME_FOR_DOCS.metric ; then
			echo "# HELP $METRIC_NAME_FOR_DOCS" >> /root/$METRIC_NAME_FOR_DOCS.metric
			echo "# TYPE $METRIC_NAME_FOR_DOCS gauge" >> /root/$METRIC_NAME_FOR_DOCS.metric
		fi
		echo "$METRIC_NAME $METRIC_VALUE" >> /root/$METRIC_NAME_FOR_DOCS.metric
	fi
}

function merge_metrics_data
{
	## Save mysql_s3_backup_successful metric
	head -n3 /root/metrics.txt > /root/mysql_s3_backup_successful.metric
	mv /root/mysql_s3_backup_successful.metric /root/metrics.txt

	## Append all other metrics
	cat *.metric >> /root/metrics.txt

	## Cleanup
	rm *.metric
}
