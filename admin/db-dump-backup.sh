#!/bin/sh

# Run this on backup machine (currently, "mtserver") to copy database dump files
# from either SYB_JAC or SYB_JAC2 database servers.

# Parent backup directory, on backup machine.
backup_dir='/export/data/sybase/db-dump'

# On omp{3,4} for any of SYB_JAC{,2} database servers.
dump_dir='/opt/omp/db-dump'

make_backup()
{
  db_host=
  db_server=
  case $# in
    1 )
      # XXX  Update $db_host assignment when standby & primary server roles change.
      case $@ in
        *jac | *JAC | *primary )
          db_host='omp3'
          db_server='SYB_JAC'
        ;;

        *jac2 | *JAC2 | *secondary | *stand*by )
          db_host='omp4'
          db_server='SYB_JAC2'
        ;;

        * )
          printf "Could not determine database host machine and server name from input: %s\n" "$*" >&2
          exit 1
        ;;
      esac
    ;;

    * )
      printf "Provide only -jac or -jac2 option to backup related database dumps.\n" >&2
      exit 1
    ;;
  esac

  nice rsync -rltgDz --quite --delete-after --size-only --bwlimit=10000  \
    "${db_host}:${dump_dir}"  \
    "${backup_dir}/${db_server}"
}

make_backup -jac
make_backup -jac2


