#!/bin/sh

#  About ddlgen:
#    http://infocenter.sybase.com/help/index.jsp?topic=/com.sybase.infocenter.dc30191.1570/html/utilityguide/CHDBBGGC.htm
#
#  ddlgnen command is found on omp[34] in Sybse ASE 15 install directory
#  ("/opt2/sybase/ase-15.0").

#  NOTE: NEED TO PROVIDE THE USER PASSWORD, VIA "-P" OPTION, IF RUNNING WITHIN
#  THE SCRIPT INSTEAD OF ON THE COMMAND LINE.


SYBROOT='/opt2/sybase/ase-15.0'
export SYBROOT

SYBASE="${SYBROOT}"
export SYBASE

SYBASE_JRE7_32="${SYBROOT}/shared/JRE-7_0_7_32BIT"
export SYBASE_JRE7_32
SYBASE_JRE7_64="${SYBROOT}/shared/JRE-7_0_7_64BIT"
export SYBASE_JRE7_64
SYBASE_JRE7="${SYBASE_JRE7_64}"
export SYBASE_JRE7

DDLGen="${SYBASE}/ASE-15_0/bin/ddlgen"

server='SYB_JAC'
interfaces="${SYBASE}/interfaces"
#  Set database userid & password as appropriate
user='sa'

now=$( date '+%Y-%m%d-%H%M' )
outfile="ddl.${now}"
progress="progress.${now}"

#  Generate date directory.
ddl_dir='ddl/'${now%-*}
mkdir -p "${ddl_dir}" || exit 2


#  Type of object.
login_opt='L'
user_opt='USR'
db_opt='DB'
db_device_opt='DBD'
table_opt='U'
view_opt='V'
index_opt='I'
trigger_opt='TR'
stored_proc_opt='P'

unset password
printf "> Enter password for Sybase ASE user '%s': " "${user}"
read password
printf "\n"

run_ddlgen()
{
  local out prog
  out="$1"  ; shift
  prog="$1" ; shift

  set -- $@

  {
    printf "* Getting information with: %s\n" "${*}"
    printf ">> DDL output  : %s\n" "${ddl_dir}/${out}"
    printf ">> progress log: %s\n" "${prog}"
  } >&2

  touch "${prog}" && tail -f "${prog}" &
  reap=$!

  ${DDLGen} -S "${server}" -I "${interfaces}" \
    -P "${password}" -U "${user}" \
    -O "${ddl_dir}/${out}"  \
    -L "${prog}" \
    $@

  sleep 1 && kill -9 $reap
}

#  Prints DDL for ...
#    database owner,
#    database options,
#    users,
#    tables,
#    grant options (on table),
#    table indexen,
#    table triggers,
#    foreign key constraints,
#    stored procedures
#
#  Feel free to ignore the objects with names "rs_*" as they are related to
#  replication & Replication Server.
show_db()
{
  local name
  name="$1"
  shift

  printf "##  Database: %s\n" "${name}"

  run_ddlgen \
    "${name}.${outfile}"  \
    "${name}.${progress}" \
    -T "${db_opt}" "-N ${name}"
}

for db in omp ukirt jcmt jcmt_tms
do
  show_db "${db}"
done

