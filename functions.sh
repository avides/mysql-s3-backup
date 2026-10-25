#!/bin/bash

function backup_mysql_and_upload
{
    DB_HOST=$1
    DB_PORT=$2
    DB_USER=$3
    DB_PASSWORD=$4

    backup_mysql $DB_HOST $DB_PORT $DB_USER $DB_PASSWORD

    ## Total duration and time of the last successful backup (kept across failed runs)
    add_metric "mysql_s3_backup_total_duration_in_ms" $(($(($(date +%s%N)/1000000)) - $BACKUP_START_TIME_IN_MS))
    if [ $BACKUP_SUCCESSFUL -eq 1 ]; then
        printf '# HELP mysql_s3_backup_last_success_timestamp\n# TYPE mysql_s3_backup_last_success_timestamp gauge\nmysql_s3_backup_last_success_timestamp %s\n' $(($(date +%s%N)/1000000)) > /root/last_success.prom
    fi

    ## create metrics
    merge_metrics_data
}

function backup_mysql
{
    DB_HOST=$1
    DB_PORT=$2
    DB_USER=$3
    DB_PASSWORD=$4
    START_DATE=$(date +"%Y-%m-%d")

    echo "Host $DB_HOST:$DB_PORT started ($(date))"

    ## Password via environment, not visible in the process list
    export MYSQL_PWD=$DB_PASSWORD

    if ! DATABASE_NAMES=$(mysql -NBA --host=$DB_HOST --port=$DB_PORT --user=$DB_USER -e 'show databases' -s --skip-column-names | grep -Evi "information_schema|performance_schema|sys|innodb|mysql|tmp") || [ -z "$DATABASE_NAMES" ]; then
        echo "ERROR: Listing databases on $DB_HOST:$DB_PORT failed"
        set_backup_failed
        return
    fi

    for database_name in $DATABASE_NAMES; do
        echo " > Database $database_name@$DB_HOST started ($(date))"

        if ! TABLE_NAMES=$(mysql -NBA --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --database=$database_name -e 'show tables'); then
            echo " > Database $database_name@$DB_HOST FAILED (listing tables)"
            set_backup_failed
            continue
        fi

        for table_name in $TABLE_NAMES; do
            echo " > > Table $table_name@$database_name@$DB_HOST started ($(date))"
            START_TIME_IN_MS=$(($(date +%s%N)/1000000))

            ## Stream dump to S3, count the bytes on the way
            mkfifo size_pipe upload_pipe
            wc -c < size_pipe > size.txt &
            PIDOF_SIZE_COUNTER=$!
            aws s3 cp - s3://$BUCKET_NAME/$START_DATE/$MYSQL_HOST_ALIAS/$database_name/$table_name.sql.gz ${S3_STORAGE_CLASS:+--storage-class $S3_STORAGE_CLASS} < upload_pipe &
            PIDOF_UPLOAD=$!

            ## The upload only completes when its input is closed - a failed dump kills it before,
            ## so no incomplete file replaces a backup (the lifecycle rule removes the aborted upload)
            exec 3> upload_pipe
            set -o pipefail
            mysqldump --single-transaction --max_allowed_packet=512M --host=$DB_HOST --port=$DB_PORT --user=$DB_USER $database_name $table_name | pigz | tee size_pipe >&3
            DUMP_RESULT=$?
            set +o pipefail

            if [ $DUMP_RESULT -ne 0 ]; then
                kill $PIDOF_UPLOAD
            fi
            exec 3>&-
            wait $PIDOF_UPLOAD
            UPLOAD_RESULT=$?

            wait $PIDOF_SIZE_COUNTER
            rm size_pipe upload_pipe

            ## Validate dump and upload, then update metrics
            if [ $DUMP_RESULT -ne 0 ] || [ $UPLOAD_RESULT -ne 0 ]; then
                echo " > > Table $table_name@$database_name@$DB_HOST FAILED ($(date))"
                set_backup_failed
                continue
            fi

            add_metric "mysql_s3_backup_file_size_in_bytes{database=\"$(escape_label "$database_name")\",table=\"$(escape_label "$table_name")\"}" $(cat size.txt)
            add_metric "mysql_s3_backup_duration_in_ms{database=\"$(escape_label "$database_name")\",table=\"$(escape_label "$table_name")\"}" $(($(($(date +%s%N)/1000000)) - $START_TIME_IN_MS))

            echo " > > Table $table_name@$database_name@$DB_HOST finished ($(date))"
        done

        echo " > Database $database_name@$DB_HOST finished ($(date))"
    done

    rm -f size.txt

    echo "Host $DB_HOST:$DB_PORT finished ($(date))"
}

function set_backup_failed
{
    ## Published with the final snapshot, until then the result of the last run stays visible
    BACKUP_SUCCESSFUL=0
}

function abort_backup
{
    echo "ERROR: $1"
    sed "s/^mysql_s3_backup_successful .*/mysql_s3_backup_successful 0/" /root/metrics.txt > /root/metrics.tmp
    mv /root/metrics.tmp /root/metrics.txt
    exit 1
}

function publish_start
{
    ## Publish the start right away, everything else of the last run stays until the final snapshot
    add_metric "mysql_s3_backup_start_timestamp" $BACKUP_START_TIME_IN_MS
    {
        head -n3 /root/metrics.txt
        cat /root/mysql_s3_backup_start_timestamp.metric
        tail -n +4 /root/metrics.txt | grep -v "mysql_s3_backup_start_timestamp"
    } > /root/metrics.tmp
    mv /root/metrics.tmp /root/metrics.txt
}

function escape_label
{
    ## Prometheus text format: backslash and double quote must be escaped in label values
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

function add_metric
{
    METRIC_NAME=$1
    METRIC_VALUE=$2
    METRIC_NAME_FOR_DOCS=$(echo "$METRIC_NAME" | cut -f1 -d"{")

    if [ ! -f /root/$METRIC_NAME_FOR_DOCS.metric ] ; then
        touch /root/$METRIC_NAME_FOR_DOCS.metric
    fi

    if ! grep -qF "$METRIC_NAME" /root/$METRIC_NAME_FOR_DOCS.metric ; then
        if ! grep -qF "$METRIC_NAME_FOR_DOCS" /root/$METRIC_NAME_FOR_DOCS.metric ; then
            echo "# HELP $METRIC_NAME_FOR_DOCS" >> /root/$METRIC_NAME_FOR_DOCS.metric
            echo "# TYPE $METRIC_NAME_FOR_DOCS gauge" >> /root/$METRIC_NAME_FOR_DOCS.metric
        fi
        echo "$METRIC_NAME $METRIC_VALUE" >> /root/$METRIC_NAME_FOR_DOCS.metric
    fi
}

function merge_metrics_data
{
    ## Build the new snapshot next to metrics.txt and replace it atomically
    printf '# HELP mysql_s3_backup_successful\n# TYPE mysql_s3_backup_successful gauge\nmysql_s3_backup_successful %s\n' $BACKUP_SUCCESSFUL > /root/metrics.tmp
    cat /root/*.metric /root/last_success.prom >> /root/metrics.tmp 2>/dev/null
    mv /root/metrics.tmp /root/metrics.txt

    ## Cleanup
    rm -f /root/*.metric
}
