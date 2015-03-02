#!/bin/sh

case $# in
  0 )
    printf "Give a list of userid, name (& email address) in CSV format.\n" >&2
    exit 1
  ;;
esac

out="${0##*/}"
out="${out%.sh}--USERID-ONLY"
printf "Writing sorted userid-only list to %s\n" "${out}" >&2

awk '!/^#/ && !/^\s*$/ { print toupper( $1 ) }' $@ \
| sort -fu >| "${out}"

