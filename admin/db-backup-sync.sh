#!/bin/bash

if [ $# != 2 ]; then
    echo Usage: $0 HOST DIRECTORY >&2
    exit 1
fi

HOST="$1"
DIR="$2"

if [ ! -d "$DIR" ]; then
    echo "$0: $DIR does not exist or is not a directory" >&2
    exit 1
fi

set -e

/usr/bin/rsync \
    -e /usr/bin/ssh \
    -rptgoD --stats \
    ${HOST}:/opt/db-backups \
    ${DIR}/

exit 0
