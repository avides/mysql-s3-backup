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

	# Compute here to have the same date remplacement for all paths and files
	export S3_PATH_AFTER_DATE_REPLACEMENT=$(date +"$S3_ROOT_PATH")
	export S3_TABLE_FILENAME_AFTER_DATE_REPLACEMENT=$(date +"$S3_TABLE_FILENAME")
	export S3_DATABASE_PATH_AFTER_DATE_REPLACEMENT=$(date +"$S3_DATABASE_PATH")
	export S3_DATABASE_FILENAME_AFTER_DATE_REPLACEMENT=$(date +"$S3_DATABASE_FILENAME")
	

	for databaseName in $(mysql -NBA --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD -e 'show databases' -s --skip-column-names|egrep -vi "information_schema|performance_schema|sys|innodb|mysql|tmp");
	do
		echo "	Database $databaseName@$DB_HOST started"

		mkdir -p $STORAGE_PATH/$databaseName
		mkdir -p dump_logs/$databaseName

		if [ "${S3_BACKUP_TYPE}" = "DATABASE" ] || [ "${S3_BACKUP_TYPE}" = "ALL" ]; then
			backup_mysql_database $DB_HOST $DB_PORT $DB_USER $DB_PASSWORD $STORAGE_PATH $databaseName
		fi

		if [ "${S3_BACKUP_TYPE}" = "TABLES" ] || [ "${S3_BACKUP_TYPE}" = "ALL" ]; then
			backup_mysql_tables $DB_HOST $DB_PORT $DB_USER $DB_PASSWORD $STORAGE_PATH $databaseName
		fi

		sync_to_s3 

		## Cleanup
		rm -rf $STORAGE_PATH/$databaseName
		rm -r dump_logs

		echo "	Database $databaseName@$DB_HOST finished"
	done

	echo "Host $DB_HOST finished ($(date))"
}

function backup_mysql_tables
{
	echo "	  Backup each table of database $databaseName@$DB_HOST started"

	DB_HOST=$1
	DB_PORT=$2
	DB_USER=$3
	DB_PASSWORD=$4
	STORAGE_PATH=$5
	databaseName=$6

	mkdir -p $STORAGE_PATH/$databaseName/tables

	for tableName in $(mysql -NBA --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD --database=$databaseName -e 'show tables')
	do
		START_TIME_IN_MS=$(($(date +%s%N)/1000000))

		## Create MySQL dump
		mkfifo pipe
		tail -n1 pipe > dump_logs/$databaseName/$tableName.log &
		PIDOF_SUCCESS_CHECK=$!

		# Replace @tableName to $tableName (for example)
		S3_TABLE_FILENAME=$(echo "$S3_TABLE_FILENAME_AFTER_DATE_REPLACEMENT" | tr "@" "$")
		# Do variable replacement ($tableName for example)
		S3_TABLE_FILENAME=$(eval echo $S3_TABLE_FILENAME)

		mysqldump --max_allowed_packet=512M --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD $databaseName $tableName | tee pipe | gzip > $STORAGE_PATH/$databaseName/tables/$S3_TABLE_FILENAME.sql.gz
		rm pipe
		wait $PIDOF_SUCCESS_CHECK

		## Validate if MySQL is completed and update metrics
		if ! grep "Dump completed on" dump_logs/$databaseName/$tableName.log; then
			sed -i -e "s/mysql_s3_backup_successful.[0-9].*/mysql_s3_backup_successful 0/g" /root/metrics.txt
			return;
		fi

		## Create file size metrics
		add_metric "mysql_s3_backup_file_size_in_bytes{database=\"${databaseName}\",table=\"${tableName}\"}" $(wc -c < $STORAGE_PATH/$databaseName/tables/$S3_TABLE_FILENAME.sql.gz)
		add_metric "mysql_s3_backup_duration_in_ms{database=\"${databaseName}\",table=\"${tableName}\"}" $(($(($(date +%s%N)/1000000)) - $START_TIME_IN_MS))

	done

	echo "	  Backup each table of database $databaseName@$DB_HOST finished"
}

function backup_mysql_database
{
	echo "	  Backup whole database $databaseName@$DB_HOST started"

	DB_HOST=$1
	DB_PORT=$2
	DB_USER=$3
	DB_PASSWORD=$4
	STORAGE_PATH=$5
	databaseName=$6

	START_TIME_IN_MS=$(($(date +%s%N)/1000000))

	## Create MySQL dump
	mkfifo pipeDatabase
	tail -n1 pipeDatabase > dump_logs/$databaseName.log &
	PIDOF_SUCCESS_CHECK=$!

	# Replace @tableName to $tableName (for example)
	dumpPath=$(echo "$S3_DATABASE_PATH_AFTER_DATE_REPLACEMENT" | tr "@" "$")
	# Do variable replacement ($tableName for example)
	dumpPath=$(eval echo $dumpPath)
	mkdir -p $STORAGE_PATH/$databaseName/$dumpPath

	# Replace @tableName to $tableName (for example)
	dumpFilename=$(echo "$S3_DATABASE_FILENAME_AFTER_DATE_REPLACEMENT" | tr "@" "$")
	# Do variable replacement ($tableName for example)
	dumpFilename=$(eval echo $dumpFilename)

	dumpFilepath=$STORAGE_PATH/$databaseName/$dumpPath/$dumpFilename.sql.gz

	mysqldump --max_allowed_packet=512M --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --password=$DB_PASSWORD $databaseName | tee pipeDatabase | gzip > $dumpFilepath
	rm pipeDatabase
	wait $PIDOF_SUCCESS_CHECK

	## Validate if MySQL is completed and update metrics
	if ! grep "Dump completed on" dump_logs/$databaseName.log; then
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
	add_metric "mysql_s3_backup_file_size_in_bytes{database=\"${databaseName}\",table=\"ALL\"}" $(wc -c < $dumpFilepath)
	add_metric "mysql_s3_backup_duration_in_ms{database=\"${databaseName}\",table=\"ALL\"}" $(($(($(date +%s%N)/1000000)) - $START_TIME_IN_MS))

	echo "	  Backup whole database $databaseName@$DB_HOST started"
}

function sync_to_s3
{
		# Replace @tableName to $tableName (for example)
		S3_PATH=$(echo "$S3_PATH_AFTER_DATE_REPLACEMENT" | tr "@" "$")
		# Do variable replacement ($tableName for example)
		S3_PATH=$(eval echo $S3_PATH)

		## Sync to S3 and remove temp files
		aws s3 cp --recursive "$STORAGE_PATH/$databaseName/" s3://$BUCKET_NAME/$S3_PATH/
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
