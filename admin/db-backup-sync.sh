#!/bin/bash

INVOKE="nice"
DAYS=""
KEEP=""
KEEPBACK=10

while [[ "$1" =~ ^- ]]; do
    case "$1" in
        -n|--dry-run)
            # Dry-run mode.
            INVOKE="echo"
            ;;
        --days)
            # Try to transfer this many days of backups (other than today),
            # otherwise rsync the whole directory.  Note: in this mode,
            # rsync the date directories themselves rather than the top level
            # directory into the target directory.
            shift
            DAYS=$1
            ;;
        --keep)
            # Keep this many days of backups.  (Other than today.)
            # (Assumes the directory structure of --days option.)
            shift
            KEEP=$1
            ;;
        *)
            echo "$0: Unknown option $1"
            exit 1
            ;;
    esac
    shift
done

if [ $# != 2 ]; then
    echo Usage: $0 OPTIONS... HOST DIRECTORY >&2
    exit 1
fi

HOST="$1"
DIR="$2"

if [ ! -d "$DIR" ]; then
    echo "$0: $DIR does not exist or is not a directory" >&2
    exit 1
fi

set -e

OPTS="-e /usr/bin/ssh -rptgoD --stats"

if [ -z "$DAYS" ]; then
    $INVOKE /usr/bin/rsync $OPTS \
        ${HOST}:/opt/db-backups \
        ${DIR}/
else
    for AGO in `seq 0 $DAYS`; do
        DATE=`date -d "$AGO days ago" +%Y%m%d`
        $INVOKE /usr/bin/rsync $OPTS \
            ${HOST}:/opt/db-backups/${DATE} \
            ${DIR}/
    done
fi

if [ -n "$KEEP" ]; then
    for AGO in `seq $(( $KEEP + 1 )) $(( $KEEP + $KEEPBACK ))`; do
        DATE=`date -d "$AGO days ago" +%Y%m%d`
        DATEDIR="${DIR}/${DATE}"
        if [ -e "$DATEDIR" ]; then
            $INVOKE rm -r $DATEDIR
        else
            echo "Directory $DATEDIR already does not exist"
        fi
    done
fi

exit 0
