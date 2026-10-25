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
    if [[ $BACKUP_SUCCESSFUL -eq 1 ]]; then
        printf '# HELP mysql_s3_backup_last_success_timestamp\n# TYPE mysql_s3_backup_last_success_timestamp gauge\nmysql_s3_backup_last_success_timestamp %s\n' $(($(date +%s%N)/1000000)) > /app/data/last_success.prom
    fi

    ## create metrics
    merge_metrics_data
    return 0
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

    if ! DATABASE_NAMES=$(mysql -NBA --host=$DB_HOST --port=$DB_PORT --user=$DB_USER -e 'show databases' -s --skip-column-names | grep -Evi "information_schema|performance_schema|sys|innodb|mysql|tmp") || [[ -z "$DATABASE_NAMES" ]]; then
        echo "ERROR: Listing databases on $DB_HOST:$DB_PORT failed" >&2
        set_backup_failed
        return
    fi

    for database_name in $DATABASE_NAMES; do
        echo " > Database $database_name@$DB_HOST started ($(date))"

        ## Tables with their engine (views have none)
        if ! TABLES=$(mysql -NBA --host=$DB_HOST --port=$DB_PORT --user=$DB_USER --database=$database_name -e "select table_name, coalesce(engine, 'VIEW') from information_schema.tables where table_schema = database()"); then
            echo " > Database $database_name@$DB_HOST FAILED (listing tables)"
            set_backup_failed
            continue
        fi

        while IFS=$'\t' read -r -u 4 table_name table_engine; do
            if [[ -z $table_name ]]; then
                continue
            fi

            ## A consistent snapshot needs a transaction, tables without transactions (e.g. MyISAM) are locked while they are dumped
            if [[ $table_engine == "InnoDB" || $table_engine == "VIEW" ]]; then
                CONSISTENCY_OPTION=--single-transaction
            else
                CONSISTENCY_OPTION=--lock-tables
            fi

            echo " > > Table $table_name@$database_name@$DB_HOST started ($(date))"
            START_TIME_IN_MS=$(($(date +%s%N)/1000000))

            ## Stream dump to S3: dd collects 1 MB blocks for the upload (the dump writes small blocks, every
            ## further pipe stage would be woken up for each of them) and reports the bytes for the metrics
            mkfifo upload_pipe
            aws s3 cp - "s3://$BUCKET_NAME/$START_DATE/$MYSQL_HOST_ALIAS/$database_name/$table_name.sql.gz" ${S3_STORAGE_CLASS:+--storage-class $S3_STORAGE_CLASS} < upload_pipe &
            PIDOF_UPLOAD=$!

            ## The upload only completes when its input is closed - a failed dump kills it before,
            ## so no incomplete file replaces a backup (the lifecycle rule removes the aborted upload)
            exec 3> upload_pipe
            set -o pipefail
            mysqldump $CONSISTENCY_OPTION --max_allowed_packet=512M --host=$DB_HOST --port=$DB_PORT --user=$DB_USER "$database_name" "$table_name" | pigz -p $PIGZ_THREADS | dd bs=1M iflag=fullblock 2> dd.log >&3
            DUMP_RESULT=$?
            set +o pipefail

            if [[ $DUMP_RESULT -ne 0 ]]; then
                kill $PIDOF_UPLOAD
            fi
            exec 3>&-
            wait $PIDOF_UPLOAD
            UPLOAD_RESULT=$?

            rm upload_pipe

            ## Validate dump and upload, then update metrics
            if [[ $DUMP_RESULT -ne 0 || $UPLOAD_RESULT -ne 0 ]]; then
                echo " > > Table $table_name@$database_name@$DB_HOST FAILED ($(date))"
                set_backup_failed
                continue
            fi

            add_metric "mysql_s3_backup_file_size_in_bytes{database=\"$(escape_label "$database_name")\",table=\"$(escape_label "$table_name")\"}" $(awk '/bytes/ {print $1}' dd.log)
            add_metric "mysql_s3_backup_duration_in_ms{database=\"$(escape_label "$database_name")\",table=\"$(escape_label "$table_name")\"}" $(($(($(date +%s%N)/1000000)) - $START_TIME_IN_MS))

            echo " > > Table $table_name@$database_name@$DB_HOST finished ($(date))"
        done 4<<< "$TABLES"

        echo " > Database $database_name@$DB_HOST finished ($(date))"
    done

    rm -f dd.log

    echo "Host $DB_HOST:$DB_PORT finished ($(date))"
    return 0
}

function cpu_limit
{
    local quota period

    ## CPU limit of the container (cgroup v2, then v1), rounded up - without a limit all CPUs
    if [[ -r /sys/fs/cgroup/cpu.max ]]; then
        read -r quota period < /sys/fs/cgroup/cpu.max
    elif [[ -r /sys/fs/cgroup/cpu/cpu.cfs_quota_us ]]; then
        quota=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)
        period=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)
    fi

    if [[ $quota =~ ^[0-9]+$ && $period =~ ^[0-9]+$ && $period -gt 0 ]]; then
        echo $(((quota + period - 1) / period))
    else
        nproc
    fi
    return 0
}

function set_backup_failed
{
    ## Published with the final snapshot, until then the result of the last run stays visible
    BACKUP_SUCCESSFUL=0
    return 0
}

function abort_backup
{
    local message=$1

    echo "ERROR: $message" >&2
    sed "s/^mysql_s3_backup_successful .*/mysql_s3_backup_successful 0/" /app/data/metrics.txt > /app/data/metrics.tmp
    mv /app/data/metrics.tmp /app/data/metrics.txt
    exit 1
}

function publish_start
{
    ## Publish the start right away, everything else of the last run stays until the final snapshot
    add_metric "mysql_s3_backup_start_timestamp" $BACKUP_START_TIME_IN_MS
    {
        head -n3 /app/data/metrics.txt
        cat /app/data/mysql_s3_backup_start_timestamp.metric
        tail -n +4 /app/data/metrics.txt | grep -Ev "^(# (HELP|TYPE) )?mysql_s3_backup_start_timestamp( |$)"
    } > /app/data/metrics.tmp
    mv /app/data/metrics.tmp /app/data/metrics.txt
    return 0
}

function escape_label
{
    local value=$1

    ## Prometheus text format: backslash and double quote must be escaped in label values
    printf '%s' "$value" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
    return 0
}

function add_metric
{
    METRIC_NAME=$1
    METRIC_VALUE=$2
    METRIC_NAME_FOR_DOCS=$(echo "$METRIC_NAME" | cut -f1 -d"{")

    if [[ ! -f /app/data/$METRIC_NAME_FOR_DOCS.metric ]] ; then
        touch /app/data/$METRIC_NAME_FOR_DOCS.metric
    fi

    if ! grep -qF "$METRIC_NAME" /app/data/$METRIC_NAME_FOR_DOCS.metric ; then
        if ! grep -qF "$METRIC_NAME_FOR_DOCS" /app/data/$METRIC_NAME_FOR_DOCS.metric ; then
            echo "# HELP $METRIC_NAME_FOR_DOCS" >> /app/data/$METRIC_NAME_FOR_DOCS.metric
            echo "# TYPE $METRIC_NAME_FOR_DOCS gauge" >> /app/data/$METRIC_NAME_FOR_DOCS.metric
        fi
        echo "$METRIC_NAME $METRIC_VALUE" >> /app/data/$METRIC_NAME_FOR_DOCS.metric
    fi
    return 0
}

function merge_metrics_data
{
    ## Build the new snapshot next to metrics.txt and replace it atomically
    printf '# HELP mysql_s3_backup_successful\n# TYPE mysql_s3_backup_successful gauge\nmysql_s3_backup_successful %s\n' $BACKUP_SUCCESSFUL > /app/data/metrics.tmp
    cat /app/data/*.metric /app/data/last_success.prom >> /app/data/metrics.tmp 2>/dev/null
    mv /app/data/metrics.tmp /app/data/metrics.txt

    ## Cleanup
    rm -f /app/data/*.metric
    return 0
}
