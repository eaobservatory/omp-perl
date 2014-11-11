#!/bin/sh

PATH='/bin:/usr/bin'
export PATH

host=$( hostname )

printf "%s : space taken by Sybase & database dumps\n\n" \
  "${host}"

df -hP  \
  /opt2/sybase/  \
  /opt/omp/  \
  /opt/omp/db-dump/  \
| uniq

