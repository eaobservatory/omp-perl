#!/bin/bash

# This script requires a my.cnf file in the backup directory, e.g.:
#
# [mariabackup]
# user=bkpuser
# password=
# databases-exclude="devjcmt devomp devukirt ukirt"

set -e

TODAY=`date +'%Y%m%d'`

DIR=/opt/db-backups

mariabackup \
    --defaults-file=${DIR}/my.cnf \
    --backup \
    --target-dir=${DIR}/${TODAY}

export LC_ALL=C

# Purge any backups more than three weeks old
purge=`find /opt/db-backups -daystart -maxdepth 1 -type d -ctime +20`
if [ "X$purge" != "X" ]; then
   rm -rfv $purge
fi

exit 0
